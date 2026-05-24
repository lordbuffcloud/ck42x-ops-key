<#
.SYNOPSIS
  Generate a PRIVATE Flipper BadUSB payload with an embedded DeepSeek API key.

.DESCRIPTION
  This intentionally writes a local-only payload under private-payloads/ by default.
  The output file contains the API key in plain text because BadUSB payloads are text.
  Do not commit, upload, screenshot, or share the generated payload.
#>

[CmdletBinding()]
param(
  [string]$OutputPath = (Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) 'private-payloads\launch-deepseek-shell-agent-private-key.txt'),
  [string]$ApiKey = '',
  [switch]$Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ScriptUrl = 'https://raw.githubusercontent.com/lordbuffcloud/ck42x-ops-key/v0.2.0/scripts/ck42x-deepseek-shell.ps1'
$ScriptSha256 = '9607ce4cb26f2af09cfbffbca952bc9adcd1f8f3b68c27f7587f959c944a6f73'

function ConvertFrom-SecureStringToPlainText {
  param([securestring]$Secure)
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
  try {
    return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
  } finally {
    if ($bstr -ne [IntPtr]::Zero) {
      [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
  }
}

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
  $envKey = [Environment]::GetEnvironmentVariable('DEEPSEEK_API_KEY', 'User')
  if (-not [string]::IsNullOrWhiteSpace($envKey)) {
    $ApiKey = $envKey
  }
}

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
  $secure = Read-Host 'Paste DeepSeek API key to embed in PRIVATE payload' -AsSecureString
  $ApiKey = ConvertFrom-SecureStringToPlainText -Secure $secure
}

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
  throw 'No DeepSeek API key supplied.'
}

$escapedKey = $ApiKey.Replace("'", "''")
$mode = if ($Execute) { ' -Execute' } else { '' }
$modeComment = if ($Execute) { 'GATED EXECUTION: still requires per-command confirmation and allowlist approval.' } else { 'REVIEW ONLY: prints the DeepSeek command plan without executing commands.' }

$payload = @"
REM CK42X DeepSeek Shell Agent PRIVATE key payload
REM $modeComment
REM WARNING: this payload contains a plaintext DeepSeek API key.
REM Treat the Flipper SD card like a password. Do not commit, upload, screenshot, or share this file.
REM If this Flipper/payload is lost or shared, revoke/rotate the DeepSeek key immediately.

DELAY 1000
GUI r
DELAY 300
STRING powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "`$env:DEEPSEEK_API_KEY='$escapedKey';`$u='$ScriptUrl';`$s='$ScriptSha256';`$p=Join-Path `$env:TEMP 'ck42x-deepseek-shell.ps1';Invoke-WebRequest -UseBasicParsing `$u -OutFile `$p;`$h=(Get-FileHash `$p -Algorithm SHA256).Hash.ToLower();if(`$h -ne `$s){throw 'CK42X script SHA256 mismatch'};& `$p -ChoosePrompt$mode"
ENTER
"@

$parent = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($parent)) {
  New-Item -ItemType Directory -Force -Path $parent | Out-Null
}

Set-Content -LiteralPath $OutputPath -Value $payload -Encoding ASCII
Write-Host "Wrote PRIVATE payload: $OutputPath" -ForegroundColor Yellow
Write-Host 'This file contains a plaintext API key. Do not commit or share it.' -ForegroundColor Red
