<#
.SYNOPSIS
  Install or refresh CK42X Ops Key into %USERPROFILE%\ck42x-ops-key.

.DESCRIPTION
  Copies this project to the standard Ducky launcher path. Does not install secrets.
#>

[CmdletBinding()]
param(
  [string]$InstallPath = (Join-Path $HOME 'ck42x-ops-key')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SourceRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if ((Resolve-Path $SourceRoot).Path -eq (Resolve-Path $InstallPath -ErrorAction SilentlyContinue).Path) {
  Write-Host "Already installed at $InstallPath"
  exit 0
}

New-Item -ItemType Directory -Force -Path $InstallPath | Out-Null
$exclude = @('.git', 'logs')
Get-ChildItem -LiteralPath $SourceRoot -Force | Where-Object { $_.Name -notin $exclude } | ForEach-Object {
  Copy-Item -LiteralPath $_.FullName -Destination $InstallPath -Recurse -Force
}

Write-Host "Installed CK42X Ops Key to $InstallPath"
Write-Host "Set your API key separately, for example:"
Write-Host "[Environment]::SetEnvironmentVariable('OPENROUTER_API_KEY','REPLACE_WITH_OPENROUTER_KEY', 'User')"
