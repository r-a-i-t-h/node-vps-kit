#!/usr/bin/env pwsh
#requires -Version 7.0
<#
.SYNOPSIS
Start, stop, or restart systemd services for kit-managed Node instances.

.DESCRIPTION
Runs systemctl start, stop, or restart for one instance. Adding or removing
the boot unit is nvk-startup. Instance files and nginx are left in place.

.EXAMPLE
sudo nvk-service
sudo nvk-service -Stop -App proseden -Name www
sudo nvk-service -Start -App proseden -Name www
sudo nvk-service -Restart -App proseden -Name www
sudo nvk-service -List
# On a terminal, missing action / -App / -Name are chosen from a numbered menu.
#>
[CmdletBinding(DefaultParameterSetName = 'List')]
param(
    [Parameter(ParameterSetName = 'List')]
    [switch]$List,

    [Parameter(ParameterSetName = 'Start', Mandatory)]
    [switch]$Start,

    [Parameter(ParameterSetName = 'Stop', Mandatory)]
    [switch]$Stop,

    [Parameter(ParameterSetName = 'Restart', Mandatory)]
    [switch]$Restart,

    [Parameter(ParameterSetName = 'List')]
    [Parameter(ParameterSetName = 'Start')]
    [Parameter(ParameterSetName = 'Stop')]
    [Parameter(ParameterSetName = 'Restart')]
    [string]$App,

    [Parameter(ParameterSetName = 'List')]
    [Parameter(ParameterSetName = 'Start')]
    [Parameter(ParameterSetName = 'Stop')]
    [Parameter(ParameterSetName = 'Restart')]
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
service: kit not found. Install the kit first:

  curl -fsSL https://raw.githubusercontent.com/$repo/$ref/bootstrap.ps1 | sudo pwsh -File -
"@
}

Import-Module (Join-Path $moduleRoot 'Nvk.psm1') -Force
Set-NvkCommand 'service'

$action = $null
if ($Start) { $action = 'Start' }
elseif ($Stop) { $action = 'Stop' }
elseif ($Restart) { $action = 'Restart' }

if (-not $action) {
    $rows = @(Get-NvkServiceRows -AppId $App -Name $Name)
    Write-NvkServiceTable $rows
    if ($rows.Count -eq 0 -or $List -or -not (Test-NvkInteractive)) {
        return
    }
    $action = Resolve-NvkServiceAction
}

$target = Resolve-NvkServiceTarget -AppId $App -Name $Name -Action $action
Invoke-NvkServiceAction -Action $action -AppId $target.AppId -Name $target.Name
