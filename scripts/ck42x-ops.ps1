<#
.SYNOPSIS
  CK42X Ops Key: safe local LLM-assisted shell operations harness.

.DESCRIPTION
  This script is intended to be launched locally, including from a Flipper/Rubber Ducky
  keystroke payload. It deliberately does NOT embed API keys, download remote scripts,
  pipe remote content into PowerShell, or allow silent arbitrary execution.

  Default mode is review-only: the LLM proposes commands, but nothing executes unless
  you pass -Execute and confirm each command interactively.
#>

[CmdletBinding()]
param(
  [ValidateSet('openrouter','openai')]
  [string]$Provider = 'openrouter',

  [string]$Model = 'openai/gpt-oss-20b:free',

  [string]$PromptId = 'repo-status',

  [string]$PromptText = '',

  [string]$WorkingDirectory = (Get-Location).Path,

  [switch]$Execute,

  [switch]$ListPrompts
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$PromptFile = Join-Path $Root 'prompts\prompts.json'
$LogDir = Join-Path $Root 'logs'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Write-Section {
  param([string]$Title)
  Write-Host "`n== $Title ==" -ForegroundColor Cyan
}

function Read-TextFileSafe {
  param([string]$Path)
  if (Test-Path -LiteralPath $Path) {
    return Get-Content -LiteralPath $Path -Raw
  }
  return ''
}

function Get-PromptLibrary {
  if (-not (Test-Path -LiteralPath $PromptFile)) {
    throw "Prompt library not found: $PromptFile"
  }
  return (Get-Content -LiteralPath $PromptFile -Raw | ConvertFrom-Json)
}

function Get-ApiKey {
  param([string]$ProviderName)
  if ($ProviderName -eq 'openrouter') {
    $key = [Environment]::GetEnvironmentVariable('OPENROUTER_API_KEY', 'User')
    if ([string]::IsNullOrWhiteSpace($key)) { $key = [Environment]::GetEnvironmentVariable('OPENROUTER_API_KEY', 'Process') }
    if ([string]::IsNullOrWhiteSpace($key)) { $key = [Environment]::GetEnvironmentVariable('OPENROUTER_API_KEY', 'Machine') }
    return $key
  }

  $openAiKey = [Environment]::GetEnvironmentVariable('OPENAI_API_KEY', 'User')
  if ([string]::IsNullOrWhiteSpace($openAiKey)) { $openAiKey = [Environment]::GetEnvironmentVariable('OPENAI_API_KEY', 'Process') }
  if ([string]::IsNullOrWhiteSpace($openAiKey)) { $openAiKey = [Environment]::GetEnvironmentVariable('OPENAI_API_KEY', 'Machine') }
  return $openAiKey
}

function Get-HostContext {
  param([string]$Path)

  $gitStatus = ''
  $gitBranch = ''
  if (Get-Command git -ErrorAction SilentlyContinue) {
    Push-Location $Path
    try {
      $gitBranch = (& git branch --show-current 2>$null) -join "`n"
      $gitStatus = (& git status --short --branch 2>$null) -join "`n"
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
  }
}

function Test-CommandAllowed {
  param([string]$Command)

  $trimmed = $Command.Trim()
  if ([string]::IsNullOrWhiteSpace($trimmed)) { return $false }

  # Block obvious destructive, persistence, download-execute, credential, and obfuscation patterns.
  $blocked = @(
    'Invoke-Expression', '\biex\b', 'DownloadString', 'FromBase64String', 'EncodedCommand',
    'Invoke-WebRequest', '\biwr\b', 'Invoke-RestMethod', '\birm\b', '\bcurl\b', '\bwget\b',
    'Start-BitsTransfer', 'New-ScheduledTask', 'Register-ScheduledTask', 'schtasks',
    'Set-ItemProperty', 'New-ItemProperty', 'Remove-ItemProperty', 'reg\s+(add|delete)',
    'net\s+user', 'New-LocalUser', 'Add-LocalGroupMember', 'Set-ExecutionPolicy',
    'Remove-Item', '\brm\b', 'del\s+', 'rmdir', 'Format-Volume', 'Clear-Disk',
    'Stop-Computer', 'Restart-Computer', 'Disable-.*Defender', 'Add-MpPreference',
    'ssh\s+', 'scp\s+', 'ftp\s+', 'nc\s+', 'ncat\s+', 'openssl\s+s_client'
  )

  foreach ($pattern in $blocked) {
    if ($trimmed -match $pattern) { return $false }
  }

  # Keep auto-approval narrow. Anything outside this list is review-only even with -Execute.
  $allowed = @(
    '^Get-Location$',
    '^pwd$',
    '^Get-ChildItem(\s|$)',
    '^dir(\s|$)',
    '^git\s+status(\s|$)',
    '^git\s+diff\s+--stat(\s|$)',
    '^git\s+diff\s+--name-only(\s|$)',
    '^git\s+log\s+--oneline(\s|$)',
    '^git\s+branch(\s|$)',
    '^npm\s+(test|run\s+test|run\s+lint|run\s+build)(\s|$)',
    '^pnpm\s+(test|run\s+test|run\s+lint|run\s+build)(\s|$)',
    '^python\s+-m\s+pytest(\s|$)',
    '^pytest(\s|$)',
    '^dotnet\s+(test|build)(\s|$)',
    '^Get-Process(\s|$)',
    '^Get-Service(\s|$)'
  )

  foreach ($pattern in $allowed) {
    if ($trimmed -match $pattern) { return $true }
  }

  return $false
}

function Invoke-Llm {
  param(
    [string]$ProviderName,
    [string]$ModelName,
    [string]$ApiKey,
    [string]$SystemPrompt,
    [string]$UserPrompt
  )

  if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    $envName = if ($ProviderName -eq 'openrouter') { 'OPENROUTER_API_KEY' } else { 'OPENAI_API_KEY' }
    throw "Missing API key. Set user env var $envName first. Example: [Environment]::SetEnvironmentVariable('$envName','sk-...','User')"
  }

  $body = @{
    model = $ModelName
    messages = @(
      @{ role = 'system'; content = $SystemPrompt },
      @{ role = 'user'; content = $UserPrompt }
    )
    temperature = 0.2
  } | ConvertTo-Json -Depth 12

  if ($ProviderName -eq 'openrouter') {
    $headers = @{
      Authorization = "Bearer $ApiKey"
      'Content-Type' = 'application/json'
      'HTTP-Referer' = 'https://ck42x.com'
      'X-Title' = 'CK42X Ops Key'
    }
    $response = Invoke-RestMethod -Method Post -Uri 'https://openrouter.ai/api/v1/chat/completions' -Headers $headers -Body $body
    return $response.choices[0].message.content
  }

  $openAiHeaders = @{
    Authorization = "Bearer $ApiKey"
    'Content-Type' = 'application/json'
  }
  $openAiResponse = Invoke-RestMethod -Method Post -Uri 'https://api.openai.com/v1/chat/completions' -Headers $openAiHeaders -Body $body
  return $openAiResponse.choices[0].message.content
}

function ConvertFrom-LlmJson {
  param([string]$Text)

  $clean = $Text.Trim()
  if ($clean -match '^```') {
    $clean = $clean -replace '^```(?:json)?\s*', '' -replace '\s*```$', ''
  }

  try {
    return ($clean | ConvertFrom-Json)
  } catch {
    throw "LLM did not return valid JSON. Raw response:`n$Text"
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

$library = Get-PromptLibrary
if ($ListPrompts) {
  Write-Section 'Available prompts'
  foreach ($p in $library.prompts) {
    Write-Host ("{0,-18} {1}" -f $p.id, $p.title)
  }
  exit 0
}

$prompt = $library.prompts | Where-Object { $_.id -eq $PromptId } | Select-Object -First 1
if (-not $prompt) {
  throw "Unknown PromptId '$PromptId'. Run with -ListPrompts."
}

if (-not (Test-Path -LiteralPath $WorkingDirectory)) {
  throw "WorkingDirectory does not exist: $WorkingDirectory"
}

$ctx = Get-HostContext -Path $WorkingDirectory
$extraPrompt = if ([string]::IsNullOrWhiteSpace($PromptText)) { '' } else { "`nExtra user prompt:`n$PromptText" }

$system = @'
You are CK42X Ops Key, a cautious local shell-operations planner.
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
- Do not propose credential access, persistence, download-execute, obfuscated commands, destructive deletes, registry edits, firewall/security bypasses, remote shell, exfiltration, or admin escalation.
- If the task needs risky actions, put them in notes, not commands.
- Assume a human must review before execution.
'@

$user = @"
Prompt preset: $($prompt.title)
Preset instruction:
$($prompt.instruction)
$extraPrompt

Host context JSON:
$(($ctx | ConvertTo-Json -Depth 6))
"@

Write-Section 'CK42X Ops Key'
Write-Host "Provider: $Provider"
Write-Host "Model:    $Model"
Write-Host "Prompt:   $PromptId - $($prompt.title)"
Write-Host "Mode:     $(if ($Execute) { 'CONFIRM-BEFORE-EACH-COMMAND' } else { 'DRY-RUN / REVIEW-ONLY' })"
Write-Host "Workdir:  $WorkingDirectory"

$key = Get-ApiKey -ProviderName $Provider
$raw = Invoke-Llm -ProviderName $Provider -ModelName $Model -ApiKey $key -SystemPrompt $system -UserPrompt $user
$result = ConvertFrom-LlmJson -Text $raw

Write-Section 'LLM plan'
Write-Host $result.summary
Write-Host "Risk: $($result.risk)"
if ($result.notes) {
  Write-Host "Notes:"
  foreach ($note in $result.notes) { Write-Host "- $note" }
}

Write-Section 'Commands'
$runLog = @()
foreach ($cmd in $result.commands) {
  Write-Host "- $cmd"
  $runLog += Invoke-ConfirmedCommand -Command $cmd -Path $WorkingDirectory
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logPath = Join-Path $LogDir "ops-$stamp.json"
[ordered]@{
  timestamp = (Get-Date).ToUniversalTime().ToString('o')
  provider = $Provider
  model = $Model
  promptId = $PromptId
  workingDirectory = $WorkingDirectory
  plan = $result
  runLog = $runLog
} | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $logPath -Encoding UTF8

Write-Section 'Log'
Write-Host $logPath
