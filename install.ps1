#!/usr/bin/env pwsh
#requires -Version 7.0
<#
.SYNOPSIS
Install a Node app instance on an Ubuntu VPS (systemd + nginx).

.DESCRIPTION
Downloads a GitHub Release, writes systemd and nginx, and installs this kit
to /usr/local/lib/node-vps-kit. Requires: sudo snap install powershell --classic

.EXAMPLE
curl -fsSL https://raw.githubusercontent.com/r-a-i-t-h/node-vps-kit/main/install.ps1 |
  sudo pwsh -File - -App proseden -Name www -ServerName www.proseden.co.uk -Port 3336
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$App,

    [Parameter(Mandatory)]
    [string]$Name,

    [Parameter(Mandatory)]
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

function ConvertTo-NvkBootArgumentList {
    param([hashtable]$BoundParameters)
    $list = [System.Collections.Generic.List[string]]::new()
    foreach ($key in $BoundParameters.Keys) {
        $value = $BoundParameters[$key]
        if ($value -is [System.Management.Automation.SwitchParameter]) {
            if ($value.IsPresent) { $list.Add("-$key") }
            continue
        }
        if ($null -eq $value -or ($value -is [string] -and $value -eq '')) { continue }
        $list.Add("-$key")
        $list.Add([string]$value)
    }
    $list.ToArray()
}

function Invoke-NvkStdinKitFetch {
    $repo = if ($env:KIT_REPO) { $env:KIT_REPO } else { 'r-a-i-t-h/node-vps-kit' }
    $ref = if ($env:KIT_REF) { $env:KIT_REF } else { 'main' }
    $url = if ($ref -match '^v.*[0-9]') {
        "https://github.com/$repo/archive/refs/tags/$ref.zip"
    }
    else {
        "https://github.com/$repo/archive/refs/heads/$ref.zip"
    }
    Write-Host "install: fetching kit $repo@$ref"
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
    if (-not $root) { throw "install: kit archive missing Nvk.psm1 ($url)" }
    $pwsh = if (Test-Path -LiteralPath '/snap/bin/pwsh') { '/snap/bin/pwsh' } else { (Get-Command pwsh).Source }
    $target = Join-Path $root 'install.ps1'
    $env:NVK_REFRESHED = '1'
    $argList = ConvertTo-NvkBootArgumentList $PSBoundParameters
    try {
        & $pwsh -NoProfile -File $target @argList
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
    Invoke-NvkStdinKitFetch
    return
}

Import-Module (Join-Path $moduleRoot 'Nvk.psm1') -Force
Set-NvkCommand 'install'
Invoke-NvkSelfUpdateIfPossible -EntryName 'install.ps1' -BoundParameters $PSBoundParameters -ScriptRoot $PSScriptRoot

Install-NvkAppInstance `
    -AppId $App `
    -Name $Name `
    -Port $Port `
    -ServerName $ServerName `
    -NginxSite $NginxSite `
    -BasePath $BasePath `
    -Prefix $Prefix `
    -Repo $Repo `
    -Version $Version `
    -Archive $Archive `
    -User $User `
    -SkipNginx:$SkipNginx
