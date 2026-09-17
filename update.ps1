#!/usr/bin/env pwsh
#requires -Version 7.0
<#
.SYNOPSIS
Update one app instance to a GitHub Release.

.DESCRIPTION
Backs up data/, swaps the app tree, runs optional deploy/post-update.sh, restarts
systemd. Does not rewrite instance data (except the seed path). Does not update
this kit — run nvk-update for that.

.EXAMPLE
sudo proseden-update -Name test
sudo proseden-update -Name www -Version v0.2.0
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$App,

    [Parameter(Mandatory)]
    [string]$Name,

    [string]$Prefix,
    [string]$Repo,
    [string]$Version = 'latest',
    [Alias('Tarball')]
    [string]$Archive
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
update: kit not found. Install the kit first:

  curl -fsSL https://raw.githubusercontent.com/$repo/$ref/bootstrap.ps1 | sudo pwsh -File -
"@
}

Import-Module (Join-Path $moduleRoot 'Nvk.psm1') -Force
Set-NvkCommand 'update'

Update-NvkAppInstance `
    -AppId $App `
    -Name $Name `
    -Prefix $Prefix `
    -Repo $Repo `
    -Version $Version `
    -Archive $Archive
