#!/usr/bin/env pwsh
#requires -Version 7.0
<#
.SYNOPSIS
Show the kit revision, installable apps, host resources, and installed instances.

.DESCRIPTION
Prints the kit version and commit date, app profiles this kit can install, and a short host
summary (CPU, memory, disk, load, uptime, Node, PowerShell). Installed
instances are printed by nvk-service -List.

Does not change the kit or any instance. Root is not required.

.EXAMPLE
sudo nvk-info
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$moduleRoot = $null
if ($env:NVK_ROOT -and (Test-Path -LiteralPath (Join-Path $env:NVK_ROOT 'Nvk.psm1'))) {
    $moduleRoot = $env:NVK_ROOT
}
elseif ($PSScriptRoot -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'Nvk.psm1'))) {
    $moduleRoot = $PSScriptRoot
}
elseif (Test-Path -LiteralPath '/usr/local/lib/node-vps-kit/Nvk.psm1') {
    $moduleRoot = '/usr/local/lib/node-vps-kit'
}

if (-not $moduleRoot) {
    $repo = if ($env:KIT_REPO) { $env:KIT_REPO } else { 'r-a-i-t-h/node-vps-kit' }
    $ref = if ($env:KIT_REF) { $env:KIT_REF } else { 'main' }
    throw @"
info: kit not found. Install the kit first:

  curl -fsSL https://raw.githubusercontent.com/$repo/$ref/bootstrap.ps1 | sudo pwsh -File -
"@
}

Import-Module (Join-Path $moduleRoot 'Nvk.psm1') -Force
Set-NvkCommand 'info'
Show-NvkInfo
