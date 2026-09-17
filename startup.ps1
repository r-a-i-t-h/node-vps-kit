#!/usr/bin/env pwsh
#requires -Version 7.0
<#
.SYNOPSIS
List, remove, or re-add systemd units for kit-managed Node instances.

.DESCRIPTION
Remove is unit-only: stop, disable, delete the unit file. Instance files and
nginx are left in place. -Add recreates the unit from the template and enable --now.

.EXAMPLE
sudo nvk-startup
sudo nvk-startup -Remove -App proseden -Name www
sudo nvk-startup -Add -App proseden -Name www
sudo nvk-startup -Remove
# On a terminal, missing -App/-Name are chosen from a numbered menu.
#>
[CmdletBinding(DefaultParameterSetName = 'List')]
param(
    [Parameter(ParameterSetName = 'List')]
    [switch]$List,

    [Parameter(ParameterSetName = 'Remove', Mandatory)]
    [switch]$Remove,

    [Parameter(ParameterSetName = 'Add', Mandatory)]
    [switch]$Add,

    [Parameter(ParameterSetName = 'List')]
    [Parameter(ParameterSetName = 'Remove')]
    [Parameter(ParameterSetName = 'Add')]
    [string]$App,

    [Parameter(ParameterSetName = 'List')]
    [Parameter(ParameterSetName = 'Remove')]
    [Parameter(ParameterSetName = 'Add')]
    [string]$Name
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
startup: kit not found. Install the kit first:

  curl -fsSL https://raw.githubusercontent.com/$repo/$ref/bootstrap.ps1 | sudo pwsh -File -
"@
}

Import-Module (Join-Path $moduleRoot 'Nvk.psm1') -Force
Set-NvkCommand 'startup'

if ($Remove) {
    $target = Resolve-NvkStartupTarget -AppId $App -Name $Name -Action Remove
    Remove-NvkStartup -AppId $target.AppId -Name $target.Name
}
elseif ($Add) {
    $target = Resolve-NvkStartupTarget -AppId $App -Name $Name -Action Add
    Add-NvkStartup -AppId $target.AppId -Name $target.Name
}
else {
    Write-NvkStartupTable (Get-NvkStartup -AppId $App -Name $Name)
}
