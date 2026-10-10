#!/usr/bin/env pwsh
#requires -Version 7.0
<#
.SYNOPSIS
Serve a directory of HTML files with nginx.

.DESCRIPTION
Writes a static site. This does not install a Node app and does not proxy.

A new hostname (the usual case, a subdomain) is a file in sites-available, a
symlink in sites-enabled, and listeners on 80 and 443. Port 80 includes
/etc/nginx/snippets/nvk-https-redirect.conf, which redirects to HTTPS.

A subdirectory is a snippet included inside an existing site's TLS server.
The directory must already exist.

.EXAMPLE
sudo nvk-nginx -ServerName books.example.com -Root /var/www/books

.EXAMPLE
sudo nvk-nginx -NginxSite /etc/nginx/sites-available/www.example.com -BasePath books -Root /var/www/books

.EXAMPLE
sudo nvk-nginx
# On a terminal, missing flags are chosen from a numbered menu.
#>
[CmdletBinding()]
param(
    [string]$ServerName,
    [string]$Root,
    [string]$NginxSite,
    [string]$BasePath
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
nginx: kit not found. Install the kit first:

  curl -fsSL https://raw.githubusercontent.com/$repo/$ref/bootstrap.ps1 | sudo pwsh -File -
  sudo nvk-nginx -ServerName HOST -Root /var/www/site
"@
}

Import-Module (Join-Path $moduleRoot 'Nvk.psm1') -Force
Set-NvkCommand 'nginx'
Assert-NvkRoot

$site = Resolve-NvkStaticSiteParams `
    -ServerName $ServerName `
    -Root $Root `
    -NginxSite $NginxSite `
    -BasePath $BasePath

if ($site.Mode -eq 'hostname') {
    Install-NvkStaticHostname -ServerName $site.ServerName -Root $site.Root
}
else {
    Install-NvkStaticPath -NginxSite $site.NginxSite -BasePath $site.BasePath -Root $site.Root
}
