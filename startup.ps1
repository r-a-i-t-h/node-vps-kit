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
    [Parameter(ParameterSetName = 'Remove', Mandatory)]
    [Parameter(ParameterSetName = 'Add', Mandatory)]
    [string]$App,

    [Parameter(ParameterSetName = 'List')]
    [Parameter(ParameterSetName = 'Remove', Mandatory)]
    [Parameter(ParameterSetName = 'Add', Mandatory)]
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
    throw 'startup: kit not found (install an app first, or set NVK_ROOT)'
}

Import-Module (Join-Path $moduleRoot 'Nvk.psm1') -Force
Set-NvkCommand 'startup'
Invoke-NvkSelfUpdateIfPossible -EntryName 'startup.ps1' -BoundParameters $PSBoundParameters -ScriptRoot $PSScriptRoot

if ($Remove) {
    Remove-NvkStartup -AppId $App -Name $Name
}
elseif ($Add) {
    Add-NvkStartup -AppId $App -Name $Name
}
else {
    Write-NvkStartupTable (Get-NvkStartup -AppId $App -Name $Name)
}
