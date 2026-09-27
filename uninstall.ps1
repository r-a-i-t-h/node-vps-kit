#!/usr/bin/env pwsh
#requires -Version 7.0
<#
.SYNOPSIS
Remove one app instance (nginx, systemd, and its directory).

.DESCRIPTION
Deletes the nginx site or path-mount snippet, the systemd unit, and the instance
directory including data, backups, releases, and env. Refuses while the systemd
service is running; stop it first with nvk-service -Stop. The system user and
any Let's Encrypt certificates are left in place.

On a terminal, missing -App / -Name are chosen from menus, then the instance
name must be typed to confirm. Non-interactive runs need -Yes.

.EXAMPLE
sudo nvk-app-uninstall -App proseden -Name www

.EXAMPLE
sudo nvk-app-uninstall -App proseden -Name www -Yes

.EXAMPLE
sudo nvk-app-uninstall
# On a terminal, missing -App / -Name are chosen from menus.
#>
[CmdletBinding()]
param(
    [string]$App,
    [string]$Name,

    [string]$Prefix,
    [switch]$Yes
)

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
uninstall: kit not found. Install the kit first:

  curl -fsSL https://raw.githubusercontent.com/$repo/$ref/bootstrap.ps1 | sudo pwsh -File -
"@
}

Import-Module (Join-Path $moduleRoot 'Nvk.psm1') -Force
Set-NvkCommand 'uninstall'

$App = Resolve-NvkAppIdParam -AppId $App
$Name = Resolve-NvkInstanceNameParam -AppId $App -Name $Name -For Existing

Uninstall-NvkAppInstance `
    -AppId $App `
    -Name $Name `
    -Prefix $Prefix `
    -Yes:$Yes
