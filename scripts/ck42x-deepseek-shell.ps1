<#
.SYNOPSIS
  CK42X DeepSeek Shell Agent: quick preset prompts for a reviewed shell plan.

.DESCRIPTION
  Self-contained PowerShell CLI intended for a Flipper/Rubber Ducky launcher.
  It sends a selected preset prompt plus minimal local context to DeepSeek's
  OpenAI-compatible chat endpoint, asks for strict JSON, prints the plan, and
  defaults to dry-run/review-only behavior.

  API keys are read from local environment variables. No keys are embedded.
#>

[CmdletBinding()]
param(
  [string]$PromptId = 'repo-status',
  [string]$PromptText = '',
  [string]$WorkingDirectory = (Get-Location).Path,
  [string]$Model = 'deepseek-chat',
  [switch]$ChoosePrompt,
  [switch]$Execute,
  [switch]$ListPrompts
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Prompts = @(
  [pscustomobject]@{
    id = 'repo-status'
    title = 'Repo status and next checks'
    instruction = 'Inspect the current repository state and propose safe read-only commands to understand branch, dirty files, recent commits, and the next verification gate. Do not modify files.'
  },
  [pscustomobject]@{
    id = 'test-triage'
    title = 'Test/lint/build triage'
    instruction = 'Given the working directory context, propose the smallest useful test, lint, or build commands. Prefer existing package scripts when visible from context. Do not modify files.'
  },
  [pscustomobject]@{
    id = 'explain-error'
    title = 'Explain an error or terminal output'
    instruction = 'Use the extra prompt text as an error/output snippet. Explain the likely cause and propose safe diagnostic commands. Avoid speculative destructive fixes.'
  },
  [pscustomobject]@{
    id = 'windows-health'
    title = 'Windows health snapshot'
    instruction = 'Propose read-only PowerShell commands to inspect processes, services, disk, and basic workstation health. Do not change services, registry, Defender, firewall, scheduled tasks, startup settings, users, or groups.'
  },
  [pscustomobject]@{
    id = 'next-action'
    title = 'One next shell action'
    instruction = 'Choose the single highest-leverage safe shell check for the current directory and explain why. Prefer read-only diagnostics. Return at most two commands.'
  }
)

$LogDir = Join-Path $env:LOCALAPPDATA 'CK42X\DeepSeekShell\logs'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Write-Section {
  param([string]$Title)
  Write-Host "`n== $Title ==" -ForegroundColor Cyan
}

function Get-DeepSeekApiKey {
  $key = [Environment]::GetEnvironmentVariable('DEEPSEEK_API_KEY', 'User')
  if ([string]::IsNullOrWhiteSpace($key)) { $key = [Environment]::GetEnvironmentVariable('DEEPSEEK_API_KEY', 'Process') }
  if ([string]::IsNullOrWhiteSpace($key)) { $key = [Environment]::GetEnvironmentVariable('DEEPSEEK_API_KEY', 'Machine') }
  return $key
}

function Get-HostContext {
  param([string]$Path)

  $gitBranch = ''
  $gitStatus = ''
  $gitRecent = ''

  if (Get-Command git -ErrorAction SilentlyContinue) {
    Push-Location $Path
    try {
      $gitBranch = (& git branch --show-current 2>$null) -join "`n"
      $gitStatus = (& git status --short --branch 2>$null) -join "`n"
      $gitRecent = (& git log --oneline -5 2>$null) -join "`n"
    } finally {
      Pop-Location
    }
  }

  return [ordered]@{
    user = [Environment]::UserName
    computer = [Environment]::MachineName
    workingDirectory = $Path
    dateUtc = (Get-Date).ToUniversalTime().ToString('o')
    powershell = $PSVersionTable.PSVersion.ToString()
    gitBranch = $gitBranch
    gitStatus = $gitStatus
    gitRecent = $gitRecent
  }
}

function Test-CommandAllowed {
  param([string]$Command)

  $trimmed = $Command.Trim()
  if ([string]::IsNullOrWhiteSpace($trimmed)) { return $false }

  $blocked = @(
    'Invoke-Expression', '\biex\b', 'DownloadString', 'FromBase64String', 'EncodedCommand',
    'Invoke-WebRequest\s+.*\|', 'Invoke-RestMethod\s+.*\|', '\biwr\b\s+.*\|', '\birm\b\s+.*\|',
    '\bcurl\b\s+.*\|', '\bwget\b\s+.*\|', 'Start-BitsTransfer',
    'New-ScheduledTask', 'Register-ScheduledTask', 'schtasks',
    'Set-ItemProperty', 'New-ItemProperty', 'Remove-ItemProperty', 'reg\s+(add|delete)',
    'net\s+user', 'New-LocalUser', 'Add-LocalGroupMember', 'Set-ExecutionPolicy',
    'Remove-Item', '\brm\b', 'del\s+', 'rmdir', 'Format-Volume', 'Clear-Disk',
    'Stop-Computer', 'Restart-Computer', 'Disable-.*Defender', 'Add-MpPreference',
    'ssh\s+', 'scp\s+', 'ftp\s+', 'nc\s+', 'ncat\s+', 'openssl\s+s_client'
  )

  foreach ($pattern in $blocked) {
    if ($trimmed -match $pattern) { return $false }
  }

  $allowed = @(
    '^Get-Location$', '^pwd$',
    '^Get-ChildItem(\s|$)', '^dir(\s|$)',
    '^git\s+status(\s|$)', '^git\s+diff\s+--stat(\s|$)', '^git\s+diff\s+--name-only(\s|$)',
    '^git\s+log\s+--oneline(\s|$)', '^git\s+branch(\s|$)',
    '^npm\s+(test|run\s+test|run\s+lint|run\s+build)(\s|$)',
    '^pnpm\s+(test|run\s+test|run\s+lint|run\s+build)(\s|$)',
    '^python\s+-m\s+pytest(\s|$)', '^pytest(\s|$)',
    '^dotnet\s+(test|build)(\s|$)',
    '^Get-Process(\s|$)', '^Get-Service(\s|$)'
  )

  foreach ($pattern in $allowed) {
    if ($trimmed -match $pattern) { return $true }
  }

  return $false
}

function Invoke-DeepSeek {
  param(
    [string]$ApiKey,
    [string]$ModelName,
    [string]$SystemPrompt,
    [string]$UserPrompt
  )

  if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    throw "Missing DEEPSEEK_API_KEY. Set it locally first: [Environment]::SetEnvironmentVariable('DEEPSEEK_API_KEY','REPLACE_WITH_DEEPSEEK_KEY','User')"
  }

  $body = @{
    model = $ModelName
    messages = @(
      @{ role = 'system'; content = $SystemPrompt },
      @{ role = 'user'; content = $UserPrompt }
    )
    temperature = 0.2
    stream = $false
  } | ConvertTo-Json -Depth 12

  $headers = @{
    Authorization = "Bearer $ApiKey"
    'Content-Type' = 'application/json'
  }

  $response = Invoke-RestMethod -Method Post -Uri 'https://api.deepseek.com/chat/completions' -Headers $headers -Body $body
  return $response.choices[0].message.content
}

function ConvertFrom-AgentJson {
  param([string]$Text)

  $clean = $Text.Trim()
  if ($clean -match '^```') {
    $clean = $clean -replace '^```(?:json)?\s*', '' -replace '\s*```$', ''
  }

  try {
    return ($clean | ConvertFrom-Json)
  } catch {
    throw "DeepSeek did not return valid JSON. Raw response:`n$Text"
  }
}

function Invoke-ConfirmedCommand {
  param([string]$Command, [string]$Path)

  $allowed = Test-CommandAllowed -Command $Command
  if (-not $allowed) {
    Write-Host "BLOCKED by allowlist: $Command" -ForegroundColor Red
    return [ordered]@{ command = $Command; status = 'blocked'; output = '' }
  }

  if (-not $Execute) {
    Write-Host "DRY RUN: $Command" -ForegroundColor Yellow
    return [ordered]@{ command = $Command; status = 'dry-run'; output = '' }
  }

  $answer = Read-Host "Execute this command? [y/N] $Command"
  if ($answer -notin @('y','Y','yes','YES')) {
    return [ordered]@{ command = $Command; status = 'skipped'; output = '' }
  }

  Push-Location $Path
  try {
    $output = (& powershell.exe -NoProfile -Command $Command 2>&1) -join "`n"
    Write-Host $output
    return [ordered]@{ command = $Command; status = 'executed'; output = $output }
  } finally {
    Pop-Location
  }
}

if ($ListPrompts) {
  Write-Section 'Available DeepSeek shell prompts'
  foreach ($p in $Prompts) {
    Write-Host ("{0,-14} {1}" -f $p.id, $p.title)
  }
  exit 0
}

if ($ChoosePrompt) {
  Write-Section 'Choose a preset prompt'
  for ($i = 0; $i -lt $Prompts.Count; $i++) {
    Write-Host ("[{0}] {1,-14} {2}" -f ($i + 1), $Prompts[$i].id, $Prompts[$i].title)
  }
  $choice = Read-Host 'Prompt number or id'
  $selected = $null
  if ($choice -match '^\d+$') {
    $index = [int]$choice - 1
    if ($index -ge 0 -and $index -lt $Prompts.Count) { $selected = $Prompts[$index] }
  }
  if (-not $selected) {
    $selected = $Prompts | Where-Object { $_.id -eq $choice } | Select-Object -First 1
  }
  if (-not $selected) { throw "Unknown prompt selection: $choice" }
  $PromptId = $selected.id
}

$prompt = $Prompts | Where-Object { $_.id -eq $PromptId } | Select-Object -First 1
if (-not $prompt) {
  throw "Unknown PromptId '$PromptId'. Run with -ListPrompts."
}

if (-not (Test-Path -LiteralPath $WorkingDirectory)) {
  throw "WorkingDirectory does not exist: $WorkingDirectory"
}

$ctx = Get-HostContext -Path $WorkingDirectory
$extraPrompt = if ([string]::IsNullOrWhiteSpace($PromptText)) { '' } else { "`nExtra user prompt:`n$PromptText" }

$system = @'
You are CK42X DeepSeek Shell Agent, a cautious local shell-operations planner.
Return only valid JSON with this schema:
{
  "summary": "one concise paragraph",
  "risk": "low|medium|high",
  "commands": ["command string"],
  "notes": ["short note"]
}
Rules:
- Propose the smallest useful commands for the requested local diagnostic/task.
- Prefer read-only diagnostics first.
- Do not propose credential access, persistence, download-execute, obfuscated commands, destructive deletes, registry edits, firewall/security bypasses, remote shell, exfiltration, admin escalation, or account changes.
- If the task needs risky actions, put them in notes, not commands.
- Assume a human must review before execution.
- Return at most 5 commands.
'@

$user = @"
Prompt preset: $($prompt.title)
Preset instruction:
$($prompt.instruction)
$extraPrompt

Host context JSON:
$(($ctx | ConvertTo-Json -Depth 6))
"@

Write-Section 'CK42X DeepSeek Shell Agent'
Write-Host "Model:    $Model"
Write-Host "Prompt:   $PromptId - $($prompt.title)"
Write-Host "Mode:     $(if ($Execute) { 'CONFIRM-BEFORE-EACH-COMMAND' } else { 'DRY-RUN / REVIEW-ONLY' })"
Write-Host "Workdir:  $WorkingDirectory"

$key = Get-DeepSeekApiKey
$raw = Invoke-DeepSeek -ApiKey $key -ModelName $Model -SystemPrompt $system -UserPrompt $user
$result = ConvertFrom-AgentJson -Text $raw

Write-Section 'DeepSeek plan'
Write-Host $result.summary
Write-Host "Risk: $($result.risk)"
if ($result.notes) {
  Write-Host 'Notes:'
  foreach ($note in $result.notes) { Write-Host "- $note" }
}

Write-Section 'Commands'
$runLog = @()
foreach ($cmd in $result.commands) {
  Write-Host "- $cmd"
  $runLog += Invoke-ConfirmedCommand -Command $cmd -Path $WorkingDirectory
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logPath = Join-Path $LogDir "deepseek-shell-$stamp.json"
[ordered]@{
  timestamp = (Get-Date).ToUniversalTime().ToString('o')
  model = $Model
  promptId = $PromptId
  workingDirectory = $WorkingDirectory
  plan = $result
  runLog = $runLog
} | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $logPath -Encoding UTF8

Write-Section 'Log'
Write-Host $logPath
