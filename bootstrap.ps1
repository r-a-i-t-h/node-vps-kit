#!/usr/bin/env pwsh
#requires -Version 7.0
<#
.SYNOPSIS
Install or update node-vps-kit on this Ubuntu VPS.

.DESCRIPTION
Fetches this kit from GitHub into /usr/local/lib/node-vps-kit and writes PATH
wrappers (nvk-update, nvk-startup, <app>-install, <app>-update). App profiles
under apps/ are included, so a kit update is how new apps appear on the box.

Does not install an app instance. After this, run <app>-install.

.EXAMPLE
curl -fsSL https://raw.githubusercontent.com/r-a-i-t-h/node-vps-kit/main/bootstrap.ps1 |
  sudo pwsh -File -

.EXAMPLE
sudo nvk-update
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

function Get-NvkBootstrapRepo {
    if ($env:KIT_REPO) { return $env:KIT_REPO }
    'r-a-i-t-h/node-vps-kit'
}

function Get-NvkBootstrapRef {
    if ($env:KIT_REF) { return $env:KIT_REF }
    'main'
}

function Invoke-NvkBootstrapFetch {
    $repo = Get-NvkBootstrapRepo
    $ref = Get-NvkBootstrapRef
    $url = if ($ref -match '^v.*[0-9]') {
        "https://github.com/$repo/archive/refs/tags/$ref.zip"
    }
    else {
        "https://github.com/$repo/archive/refs/heads/$ref.zip"
    }
    Write-Host "kit: fetching $repo@$ref"
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("nvk-boot-" + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $zip = Join-Path $tmp 'kit.zip'
    $headers = @{ 'User-Agent' = 'node-vps-kit' }
    if ($env:GITHUB_TOKEN) { $headers.Authorization = "Bearer $($env:GITHUB_TOKEN)" }
    Invoke-WebRequest -Uri $url -OutFile $zip -Headers $headers -UseBasicParsing
    $extract = Join-Path $tmp 'extract'
    New-Item -ItemType Directory -Path $extract -Force | Out-Null
    Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force
    $root = $null
    if (Test-Path -LiteralPath (Join-Path $extract 'Nvk.psm1')) {
        $root = $extract
    }
    else {
        foreach ($child in Get-ChildItem -LiteralPath $extract -Directory) {
            if (Test-Path -LiteralPath (Join-Path $child.FullName 'Nvk.psm1')) {
                $root = $child.FullName
                break
            }
        }
    }
    if (-not $root) { throw "kit: archive missing Nvk.psm1 ($url)" }
    $pwsh = if (Test-Path -LiteralPath '/snap/bin/pwsh') { '/snap/bin/pwsh' } else { (Get-Command pwsh).Source }
    $target = Join-Path $root 'bootstrap.ps1'
    if (-not (Test-Path -LiteralPath $target)) { throw 'kit: archive missing bootstrap.ps1' }
    $env:NVK_REFRESHED = '1'
    try {
        & $pwsh -NoProfile -File $target
        $code = $LASTEXITCODE
        if ($null -eq $code) { $code = 0 }
        exit $code
    }
    finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

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
    Invoke-NvkBootstrapFetch
    return
}

Import-Module (Join-Path $moduleRoot 'Nvk.psm1') -Force
Set-NvkCommand 'kit'
Update-NvkKit
