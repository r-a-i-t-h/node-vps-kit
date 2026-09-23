#!/usr/bin/env pwsh
#requires -Version 7.0
<#
.SYNOPSIS
Install a Node app instance on an Ubuntu VPS (systemd + nginx).

.DESCRIPTION
Uses the kit already on this box (see bootstrap.ps1 / nvk-update). Downloads a
GitHub Release and writes systemd and nginx for one named instance.

.EXAMPLE
sudo nvk-app-install -App proseden -Name www -ServerName www.proseden.co.uk -Port 3336

.EXAMPLE
sudo nvk-app-install
# On a terminal, missing flags are chosen from a numbered menu.
#>
[CmdletBinding()]
param(
    [string]$App,
    [string]$Name,
    [int]$Port,

    [string]$ServerName,
    [string]$NginxSite,
    [string]$BasePath,
    [string]$Prefix,
    [string]$Repo,
    [string]$Version = 'latest',
    [Alias('Tarball')]
    [string]$Archive,
    [string]$User,
    [switch]$SkipNginx
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
install: kit not found. Install the kit first, then install the app:

  curl -fsSL https://raw.githubusercontent.com/$repo/$ref/bootstrap.ps1 | sudo pwsh -File -
  sudo nvk-app-install -App $App -Name $Name ...
"@
}

Import-Module (Join-Path $moduleRoot 'Nvk.psm1') -Force
Set-NvkCommand 'install'

$App = Resolve-NvkAppIdParam -AppId $App
$Name = Resolve-NvkInstanceNameParam -AppId $App -Name $Name -For New
$Port = Resolve-NvkPortParam -Port $Port
$nginx = Resolve-NvkNginxInstallParams `
    -ServerName $ServerName `
    -NginxSite $NginxSite `
    -BasePath $BasePath `
    -SkipNginx:$SkipNginx `
    -InstanceName $Name

Install-NvkAppInstance `
    -AppId $App `
    -Name $Name `
    -Port $Port `
    -ServerName $nginx.ServerName `
    -NginxSite $nginx.NginxSite `
    -BasePath $nginx.BasePath `
    -Prefix $Prefix `
    -Repo $Repo `
    -Version $Version `
    -Archive $Archive `
    -User $User `
    -SkipNginx:$nginx.SkipNginx
