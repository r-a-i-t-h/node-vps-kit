# Shared helpers for node-vps-kit. Used by bootstrap.ps1, install.ps1, uninstall.ps1, update.ps1, startup.ps1, service.ps1.

Set-StrictMode -Version Latest

$script:NvkKitLibDir = '/usr/local/lib/node-vps-kit'
$script:NvkCacheRoot = '/var/cache/node-vps-kit'
$script:NvkCacheKeep = 3
$script:NvkSbinDir = '/usr/local/sbin'
$script:NvkSnapPwsh = '/snap/bin/pwsh'
$script:NvkUtf8 = [System.Text.UTF8Encoding]::new($false)
$script:NvkKitRoot = $PSScriptRoot
$script:NvkCmd = 'nvk'

function Set-NvkCommand {
    param([Parameter(Mandatory)][string]$Name)
    $script:NvkCmd = $Name
}

function Get-NvkKitRepo {
    if ($env:KIT_REPO) { return $env:KIT_REPO }
    'r-a-i-t-h/node-vps-kit'
}

function Get-NvkKitRef {
    if ($env:KIT_REF) { return $env:KIT_REF }
    'main'
}

function Write-NvkInfo {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host "$($script:NvkCmd): $Message"
}

function Write-NvkError {
    param([Parameter(Mandatory)][string]$Message)
    throw "$($script:NvkCmd): $Message"
}

function Get-NvkPwshPath {
    if (Test-Path -LiteralPath $script:NvkSnapPwsh) {
        return $script:NvkSnapPwsh
    }
    $cmd = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    Write-NvkError 'pwsh not found (install: sudo snap install powershell --classic)'
}

function Invoke-NvkNative {
    param(
        [switch]$AllowFailure,
        # Drop stdout. Exit-code checks must not see it: PowerShell's -eq/-ne
        # filter arrays, so a printed line plus exit 0 is treated as failure.
        [switch]$Quiet,
        # Drop stderr as well (best-effort systemctl when the unit may be gone).
        [switch]$DiscardError,
        [Parameter(Mandatory)]
        [string[]]$Command
    )
    if (-not $Command -or $Command.Count -eq 0) {
        Write-NvkError 'Invoke-NvkNative: no command'
    }
    $exe = $Command[0]
    $rest = @()
    if ($Command.Count -gt 1) {
        $rest = $Command[1..($Command.Count - 1)]
    }
    $prev = $PSNativeCommandUseErrorActionPreference
    try {
        $global:PSNativeCommandUseErrorActionPreference = $false
        if ($DiscardError) {
            if ($Quiet) {
                & $exe @rest 2>$null | Out-Null
            }
            else {
                & $exe @rest 2>$null | Out-Host
            }
        }
        elseif ($Quiet) {
            & $exe @rest | Out-Null
        }
        else {
            & $exe @rest | Out-Host
        }
        $code = $LASTEXITCODE
        if ($null -eq $code) { $code = 0 }
        if (-not $AllowFailure -and $code -ne 0) {
            Write-NvkError "command failed ($code): $exe $($rest -join ' ')"
        }
        return [int]$code
    }
    finally {
        $global:PSNativeCommandUseErrorActionPreference = $prev
    }
}

function Test-NvkCommandExists {
    param([Parameter(Mandatory)][string]$Name)
    [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Assert-NvkCommand {
    param([Parameter(Mandatory)][string]$Name)
    if (-not (Test-NvkCommandExists $Name)) {
        Write-NvkError "missing command: $Name"
    }
}

function Write-NvkFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content
    )
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $text = $Content.TrimEnd("`r", "`n") + "`n"
    [System.IO.File]::WriteAllText($Path, $text, $script:NvkUtf8)
}

function Get-NvkGitHubHeaders {
    $headers = @{ 'User-Agent' = 'node-vps-kit' }
    if ($env:GITHUB_TOKEN) {
        $headers.Authorization = "Bearer $($env:GITHUB_TOKEN)"
    }
    $headers
}

function Save-NvkGitHubDownload {
    param(
        [Parameter(Mandatory)][string]$Url,
        [Parameter(Mandatory)][string]$Destination
    )
    $dir = Split-Path -Parent $Destination
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Invoke-WebRequest -Uri $Url -OutFile $Destination -Headers (Get-NvkGitHubHeaders) -UseBasicParsing
}

function Get-NvkKitZipUrl {
    $repo = Get-NvkKitRepo
    $ref = Get-NvkKitRef
    if ($ref -match '^v.*[0-9]') {
        return "https://github.com/$repo/archive/refs/tags/$ref.zip"
    }
    "https://github.com/$repo/archive/refs/heads/$ref.zip"
}

function Find-NvkUnpackedKit {
    param([Parameter(Mandatory)][string]$Directory)
    if (Test-Path -LiteralPath (Join-Path $Directory 'Nvk.psm1')) {
        return $Directory
    }
    foreach ($child in Get-ChildItem -LiteralPath $Directory -Directory -ErrorAction SilentlyContinue) {
        if (Test-Path -LiteralPath (Join-Path $child.FullName 'Nvk.psm1')) {
            return $child.FullName
        }
    }
    $null
}

function Get-NvkKitFromGitHub {
    $repo = Get-NvkKitRepo
    $ref = Get-NvkKitRef
    $url = Get-NvkKitZipUrl
    Write-NvkInfo "fetching kit $repo@$ref"
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("nvk-kit-" + [guid]::NewGuid().ToString('n'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    try {
        $zip = Join-Path $tmp 'kit.zip'
        Save-NvkGitHubDownload -Url $url -Destination $zip
        $extract = Join-Path $tmp 'extract'
        New-Item -ItemType Directory -Path $extract -Force | Out-Null
        Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force
        $root = Find-NvkUnpackedKit $extract
        if (-not $root) {
            Write-NvkError "kit archive missing Nvk.psm1 ($url)"
        }
        [pscustomobject]@{
            KitRoot = $root
            TempDir = $tmp
        }
    }
    catch {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        throw
    }
}

function Test-NvkIsInstalledKitRoot {
    param([Parameter(Mandatory)][string]$Root)
    try {
        $a = [System.IO.Path]::GetFullPath($Root).TrimEnd('/', '\')
        $b = [System.IO.Path]::GetFullPath($script:NvkKitLibDir).TrimEnd('/', '\')
        return $a -eq $b
    }
    catch {
        return $false
    }
}

function Get-NvkFamilyAppIds {
    param([string]$KitRoot = $script:NvkKitRoot)
    $appsDir = Join-Path $KitRoot 'apps'
    if (-not (Test-Path -LiteralPath $appsDir)) { return @() }
    Get-ChildItem -LiteralPath $appsDir -Filter '*.psd1' |
        ForEach-Object { $_.BaseName }
}

function New-NvkWrapperScript {
    param(
        [Parameter(Mandatory)][string]$Target,
        [string]$Passthrough = ''
    )
    $invoke = if ($Passthrough) {
        '& {0} {1} @args' -f "'$Target'", $Passthrough
    }
    else {
        '& {0} @args' -f "'$Target'"
    }
    @(
        '#!/snap/bin/pwsh'
        '#requires -Version 7.0'
        '$ErrorActionPreference = ''Stop'''
        '$PSNativeCommandUseErrorActionPreference = $true'
        $invoke
    ) -join "`n"
}

function Install-NvkKitAndWrappers {
    param(
        [Parameter(Mandatory)][string]$Source
    )
    $lib = $script:NvkKitLibDir
    Assert-NvkRoot
    Write-NvkInfo "installing kit to $lib"

    # Collect before replacing apps/ so prior per-app wrappers can be removed.
    $staleAppIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    if (Test-Path -LiteralPath (Join-Path $lib 'apps')) {
        foreach ($id in @(Get-NvkFamilyAppIds -KitRoot $lib)) { [void]$staleAppIds.Add($id) }
    }
    foreach ($id in @(Get-NvkFamilyAppIds -KitRoot $Source)) { [void]$staleAppIds.Add($id) }

    New-Item -ItemType Directory -Path $lib -Force | Out-Null
    if (-not (Test-NvkIsInstalledKitRoot $Source)) {
        foreach ($name in @('bootstrap.ps1', 'install.ps1', 'uninstall.ps1', 'update.ps1', 'startup.ps1', 'service.ps1', 'Nvk.psm1', 'README.md')) {
            $src = Join-Path $Source $name
            if (Test-Path -LiteralPath $src) {
                Copy-Item -LiteralPath $src -Destination (Join-Path $lib $name) -Force
            }
        }
        foreach ($dirName in @('apps', 'templates')) {
            $src = Join-Path $Source $dirName
            if (Test-Path -LiteralPath $src) {
                $dest = Join-Path $lib $dirName
                if (Test-Path -LiteralPath $dest) {
                    Remove-Item -LiteralPath $dest -Recurse -Force
                }
                Copy-Item -LiteralPath $src -Destination $dest -Recurse -Force
            }
        }
        foreach ($stale in @('install.sh', 'update.sh', 'lib', 'apps/proseden.conf')) {
            $path = Join-Path $lib $stale
            if (Test-Path -LiteralPath $path) {
                Remove-Item -LiteralPath $path -Recurse -Force
            }
        }
        foreach ($entry in @('bootstrap.ps1', 'install.ps1', 'uninstall.ps1', 'update.ps1', 'startup.ps1', 'service.ps1')) {
            $p = Join-Path $lib $entry
            if (Test-Path -LiteralPath $p) {
                Invoke-NvkNative -Command @('chmod', '755', $p) | Out-Null
            }
        }
    }

    New-Item -ItemType Directory -Path $script:NvkSbinDir -Force | Out-Null
    foreach ($id in $staleAppIds) {
        foreach ($suffix in @('install', 'update')) {
            $path = Join-Path $script:NvkSbinDir "$id-$suffix"
            if (Test-Path -LiteralPath $path) {
                Remove-Item -LiteralPath $path -Force
            }
        }
    }

    $appInstallWrap = Join-Path $script:NvkSbinDir 'nvk-app-install'
    $appUninstallWrap = Join-Path $script:NvkSbinDir 'nvk-app-uninstall'
    $appUpdateWrap = Join-Path $script:NvkSbinDir 'nvk-app-update'
    $startupWrap = Join-Path $script:NvkSbinDir 'nvk-startup'
    $serviceWrap = Join-Path $script:NvkSbinDir 'nvk-service'
    $kitUpdateWrap = Join-Path $script:NvkSbinDir 'nvk-update'
    Write-NvkFile $appInstallWrap (New-NvkWrapperScript -Target "$lib/install.ps1")
    Write-NvkFile $appUninstallWrap (New-NvkWrapperScript -Target "$lib/uninstall.ps1")
    Write-NvkFile $appUpdateWrap (New-NvkWrapperScript -Target "$lib/update.ps1")
    Write-NvkFile $startupWrap (New-NvkWrapperScript -Target "$lib/startup.ps1")
    Write-NvkFile $serviceWrap (New-NvkWrapperScript -Target "$lib/service.ps1")
    Write-NvkFile $kitUpdateWrap (New-NvkWrapperScript -Target "$lib/bootstrap.ps1")
    foreach ($wrap in @($appInstallWrap, $appUninstallWrap, $appUpdateWrap, $startupWrap, $serviceWrap, $kitUpdateWrap)) {
        Invoke-NvkNative -Command @('chmod', '755', $wrap) | Out-Null
    }

    $ids = @(Get-NvkFamilyAppIds -KitRoot $Source)
    $appList = if ($ids.Count) { $ids -join ', ' } else { '(none)' }
    Write-NvkInfo "installed wrappers in $($script:NvkSbinDir)"
    Write-NvkInfo "registered apps: $appList"
}

function Update-NvkKit {
    Assert-NvkRoot
    $source = $script:NvkKitRoot
    if (-not $source -or -not (Test-Path -LiteralPath (Join-Path $source 'Nvk.psm1'))) {
        Write-NvkError 'kit source not found'
    }

    # A GitHub fetch already unpacked this tree, or this is a checkout / NVK_ROOT.
    # Only the installed copy at /usr/local/lib/node-vps-kit pulls upstream.
    if ($env:NVK_REFRESHED -eq '1' -or -not (Test-NvkIsInstalledKitRoot $source)) {
        Install-NvkKitAndWrappers -Source $source
        return
    }

    $fetched = $null
    try {
        $fetched = Get-NvkKitFromGitHub
        $env:NVK_REFRESHED = '1'
        $target = Join-Path $fetched.KitRoot 'bootstrap.ps1'
        if (-not (Test-Path -LiteralPath $target)) {
            Write-NvkError 'refreshed kit missing bootstrap.ps1'
        }
        $pwsh = Get-NvkPwshPath
        & $pwsh -NoProfile -File $target
        $code = $LASTEXITCODE
        if ($null -eq $code) { $code = 0 }
        exit $code
    }
    finally {
        if ($fetched -and $fetched.TempDir -and (Test-Path -LiteralPath $fetched.TempDir)) {
            Remove-Item -LiteralPath $fetched.TempDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Import-NvkApp {
    param([Parameter(Mandatory)][string]$AppId)
    $conf = Join-Path $script:NvkKitRoot "apps/$AppId.psd1"
    if (-not (Test-Path -LiteralPath $conf)) {
        $available = (Get-NvkFamilyAppIds) -join ' '
        if (-not $available) { $available = '(none)' }
        Write-NvkError "unknown app '$AppId' (no $conf). Available: $available. If this is a new app, run nvk-update to fetch profiles."
    }
    $raw = Import-PowerShellDataFile -Path $conf
    if (-not $raw.AppId) { Write-NvkError "app profile missing AppId" }
    if ($raw.AppId -ne $AppId) {
        Write-NvkError "app profile AppId=$($raw.AppId) does not match -App $AppId"
    }
    if (-not $raw.Repo) { Write-NvkError 'app profile missing Repo' }
    if (-not $raw.Tarball) { Write-NvkError 'app profile missing Tarball' }

    $prefix = if ($raw.Prefix) { $raw.Prefix } else { "/opt/$($raw.AppId)" }
    $user = if ($raw.User) { $raw.User } else { $raw.AppId }
    $nodeMajor = if ($null -ne $raw.NodeMajor) { [int]$raw.NodeMajor } else { 20 }
    $archiveRoot = if ($raw.ArchiveRoot) { $raw.ArchiveRoot } else { $raw.AppId }
    $serverEntry = if ($raw.ServerEntry) { $raw.ServerEntry } else { 'dist/server.js' }
    $envPrefix = if ($raw.EnvPrefix) {
        $raw.EnvPrefix
    }
    else {
        ($raw.AppId.ToUpperInvariant() -replace '-', '_')
    }
    $health = if ($raw.HealthPath) { $raw.HealthPath } else { 'health' }
    $hasSeed = [bool]$raw.HasSeed
    $hasBasePath = [bool]$raw.HasBasePath
    $nginxExtra = if ($raw.NginxExtra) { [string]$raw.NginxExtra } else { '' }
    $envExtra = @()
    if ($raw.ContainsKey('EnvExtra') -and $null -ne $raw.EnvExtra) {
        $envExtra = @($raw.EnvExtra | ForEach-Object { [string]$_ })
    }
    $note = if ($raw.PostInstallNote) { [string]$raw.PostInstallNote } else { '' }

    [pscustomobject]@{
        AppId           = [string]$raw.AppId
        Repo            = [string]$raw.Repo
        Tarball         = [string]$raw.Tarball
        Prefix          = [string]$prefix
        User            = [string]$user
        NodeMajor       = $nodeMajor
        ArchiveRoot     = [string]$archiveRoot
        ServerEntry     = [string]$serverEntry
        EnvPrefix       = [string]$envPrefix
        HealthPath      = [string]$health
        HasSeed         = $hasSeed
        HasBasePath     = $hasBasePath
        NginxExtra      = $nginxExtra
        EnvExtra        = $envExtra
        PostInstallNote = $note
    }
}

function Assert-NvkRoot {
    $uid = (& id -u)
    if ([int]$uid -ne 0) {
        Write-NvkError 'run as root (sudo)'
    }
}

function Test-NvkName {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
    ($Name -match '^[a-zA-Z0-9_-]+$') -and -not $Name.StartsWith('-') -and -not $Name.EndsWith('_')
}

function Assert-NvkName {
    param([Parameter(Mandatory)][string]$Name)
    if (-not (Test-NvkName $Name)) {
        Write-NvkError '-Name must be letters, digits, hyphen, or underscore'
    }
}

function Assert-NvkPort {
    param([Parameter(Mandatory)][int]$Port)
    if ($Port -lt 1 -or $Port -gt 65535) {
        Write-NvkError '-Port out of range'
    }
}

function Get-NvkNodePath {
    $cmd = Get-Command node -ErrorAction SilentlyContinue
    if (-not $cmd) { Write-NvkError 'missing command: node' }
    $cmd.Source
}

function Assert-NvkNodeVersion {
    param([Parameter(Mandatory)][int]$Minimum)
    Assert-NvkCommand node
    $major = & node -p "process.versions.node.split('.')[0]"
    if ([int]$major -lt $Minimum) {
        $found = & node -v
        Write-NvkError "Node.js >= $Minimum required (found $found)"
    }
}

function ConvertTo-NvkReleaseTag {
    param([Parameter(Mandatory)][string]$Version)
    if ($Version -like 'v*') { return $Version }
    "v$Version"
}

function Get-NvkCachedAppEntries {
    param([Parameter(Mandatory)][string]$AppId)
    $root = Join-Path $script:NvkCacheRoot $AppId
    if (-not (Test-Path -LiteralPath $root)) { return @() }
    Get-ChildItem -LiteralPath $root -Directory | ForEach-Object {
        $item = $_
        $marker = Join-Path $item.FullName 'fetched'
        $when = $item.LastWriteTimeUtc
        if (Test-Path -LiteralPath $marker) {
            try {
                $when = [datetime]::Parse(
                    (Get-Content -LiteralPath $marker -Raw).Trim(),
                    [cultureinfo]::InvariantCulture,
                    [System.Globalization.DateTimeStyles]::RoundtripKind
                )
            }
            catch {
                $when = $item.LastWriteTimeUtc
            }
        }
        [pscustomobject]@{
            Tag     = $item.Name
            Path    = $item.FullName
            Fetched = $when.ToUniversalTime()
        }
    } | Sort-Object Fetched -Descending
}

function Get-NvkCachedArchiveFile {
    param(
        [Parameter(Mandatory)][string]$CacheDir,
        [string]$Tarball
    )
    if ($Tarball) {
        $named = Join-Path $CacheDir $Tarball
        if (Test-Path -LiteralPath $named) { return $named }
    }
    Get-ChildItem -LiteralPath $CacheDir -File |
        Where-Object { $_.Name -ne 'fetched' } |
        Select-Object -First 1 -ExpandProperty FullName
}

function Update-NvkCacheRecency {
    param([Parameter(Mandatory)][string]$CacheDir)
    Write-NvkFile (Join-Path $CacheDir 'fetched') ([datetime]::UtcNow.ToString('o'))
}

function Save-NvkAppArchiveCache {
    param(
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$Tag,
        [Parameter(Mandatory)][string]$ArchivePath
    )
    $dir = Join-Path (Join-Path $script:NvkCacheRoot $AppId) $Tag
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $dest = Join-Path $dir (Split-Path -Leaf $ArchivePath)
    Copy-Item -LiteralPath $ArchivePath -Destination $dest -Force
    Update-NvkCacheRecency $dir
    $entries = @(Get-NvkCachedAppEntries $AppId)
    if ($entries.Count -gt $script:NvkCacheKeep) {
        $entries | Select-Object -Skip $script:NvkCacheKeep | ForEach-Object {
            Write-NvkInfo "cache: evicting $($_.Tag)"
            Remove-Item -LiteralPath $_.Path -Recurse -Force
        }
    }
    $dest
}

function Get-NvkLatestReleaseTag {
    param(
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][string]$AppId
    )
    $api = "https://api.github.com/repos/$Repo/releases/latest"
    try {
        $release = Invoke-RestMethod -Uri $api -Headers (Get-NvkGitHubHeaders)
        if (-not $release.tag_name) { Write-NvkError "latest release has no tag_name" }
        return [string]$release.tag_name
    }
    catch {
        $cached = @(Get-NvkCachedAppEntries $AppId) | Select-Object -First 1
        if ($cached) {
            Write-NvkInfo "warning: could not read $api; using cached tag $($cached.Tag) (may not be GitHub latest)"
            return $cached.Tag
        }
        Write-NvkError "could not read $api (repo public? release published?) and no cached version"
    }
}

function Resolve-NvkReleaseTag {
    param(
        [Parameter(Mandatory)][string]$Repo,
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$Version
    )
    if ($Version -ne 'latest') {
        return (ConvertTo-NvkReleaseTag $Version)
    }
    Get-NvkLatestReleaseTag -Repo $Repo -AppId $AppId
}

function Resolve-NvkAppArchive {
    param(
        [Parameter(Mandatory)]$App,
        [Parameter(Mandatory)][string]$Tag,
        [string]$Archive
    )
    if ($Archive) {
        if (-not (Test-Path -LiteralPath $Archive)) {
            Write-NvkError "archive not found: $Archive"
        }
        return (Resolve-Path -LiteralPath $Archive).Path
    }
    $cached = @(Get-NvkCachedAppEntries $App.AppId) | Where-Object { $_.Tag -eq $Tag } | Select-Object -First 1
    if ($cached) {
        $file = Get-NvkCachedArchiveFile -CacheDir $cached.Path -Tarball $App.Tarball
        if ($file) {
            Write-NvkInfo "using cached $($App.AppId) $Tag"
            Update-NvkCacheRecency $cached.Path
            return $file
        }
    }
    $url = "https://github.com/$($App.Repo)/releases/download/$Tag/$($App.Tarball)"
    Write-NvkInfo "downloading $url"
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("nvk-dl-" + [guid]::NewGuid().ToString('n') + '-' + $App.Tarball)
    try {
        Save-NvkGitHubDownload -Url $url -Destination $tmp
        return (Save-NvkAppArchiveCache -AppId $App.AppId -Tag $Tag -ArchivePath $tmp)
    }
    finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

function Repair-NvkUnixExecuteBits {
    param([Parameter(Mandatory)][string]$ReleaseDir)
    $paths = @(
        Join-Path $ReleaseDir 'deploy'
        Join-Path $ReleaseDir 'node_modules/.bin'
    )
    foreach ($dir in $paths) {
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        Get-ChildItem -LiteralPath $dir -File -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like '*.sh' -or $_.DirectoryName -like '*node_modules/.bin*' } |
            ForEach-Object { Invoke-NvkNative -Command @('chmod', '+x', $_.FullName) | Out-Null }
    }
    foreach ($hook in @('deploy/post-update.sh', 'deploy/install.sh', 'deploy/update.sh', 'deploy/migrate.sh', 'deploy/backup-data.sh')) {
        $p = Join-Path $ReleaseDir $hook
        if (Test-Path -LiteralPath $p) {
            Invoke-NvkNative -Command @('chmod', '+x', $p) | Out-Null
        }
    }
    $migrations = Join-Path $ReleaseDir 'deploy/migrations'
    if (Test-Path -LiteralPath $migrations) {
        Get-ChildItem -LiteralPath $migrations -Filter '*.sh' -ErrorAction SilentlyContinue |
            ForEach-Object { Invoke-NvkNative -Command @('chmod', '+x', $_.FullName) | Out-Null }
    }
}

function Expand-NvkAppArchive {
    param(
        [Parameter(Mandatory)][string]$Archive,
        [Parameter(Mandatory)][string]$Destination,
        [Parameter(Mandatory)]$App
    )
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $name = $Archive.ToLowerInvariant()
    if ($name.EndsWith('.zip')) {
        Expand-Archive -LiteralPath $Archive -DestinationPath $Destination -Force
    }
    elseif ($name.EndsWith('.tar.gz') -or $name.EndsWith('.tgz')) {
        Assert-NvkCommand tar
        Invoke-NvkNative -Command @('tar', '-xzf', $Archive, '-C', $Destination) | Out-Null
    }
    else {
        Write-NvkError "unsupported archive type (want .zip or .tar.gz): $Archive"
    }
    $root = Join-Path $Destination $App.ArchiveRoot
    $entry = Join-Path $root $App.ServerEntry
    if (-not (Test-Path -LiteralPath $entry)) {
        Write-NvkError "archive missing $($App.ServerEntry)"
    }
    $root
}

function Get-NvkVersionFromRelease {
    param([Parameter(Mandatory)][string]$ReleaseDir)
    $file = Join-Path $ReleaseDir 'VERSION'
    if (Test-Path -LiteralPath $file) {
        return (Get-Content -LiteralPath $file -Raw).Trim()
    }
    $null
}

function Set-NvkCurrentSymlink {
    param(
        [Parameter(Mandatory)][string]$ReleaseDir,
        [Parameter(Mandatory)][string]$CurrentPath
    )
    Invoke-NvkNative -Command @('ln', '-sfn', $ReleaseDir, $CurrentPath) | Out-Null
}

function Initialize-NvkSystemUser {
    param(
        [Parameter(Mandatory)][string]$User,
        [Parameter(Mandatory)][string]$Home
    )
    $exists = Invoke-NvkNative -AllowFailure -Quiet -Command @('id', $User)
    if ($exists -eq 0) { return }
    Write-NvkInfo "creating system user $User"
    Assert-NvkCommand useradd
    $made = Invoke-NvkNative -AllowFailure -Command @('useradd', '--system', '--home', $Home, '--shell', '/usr/sbin/nologin', $User)
    if ($made -ne 0) {
        Invoke-NvkNative -Command @('useradd', '--system', '--home', $Home, '--shell', '/bin/false', $User) | Out-Null
    }
}

function Set-NvkOwner {
    param(
        [Parameter(Mandatory)][string]$User,
        [Parameter(Mandatory)][string[]]$Path
    )
    foreach ($p in $Path) {
        if (Test-Path -LiteralPath $p) {
            Invoke-NvkNative -Command @('chown', '-R', "${User}:${User}", $p) | Out-Null
        }
    }
}

function Expand-NvkPlaceholders {
    param(
        [Parameter(Mandatory)][string]$Text,
        [Parameter(Mandatory)][hashtable]$Map
    )
    foreach ($key in $Map.Keys) {
        $Text = $Text.Replace($key, [string]$Map[$key])
    }
    $Text
}

function Get-NvkPlaceholderMap {
    param(
        [Parameter(Mandatory)]$App,
        [Parameter(Mandatory)][string]$Name,
        [string]$Port,
        [string]$ServerName,
        [string]$BasePath,
        [string]$Prefix,
        [string]$User,
        [string]$Node,
        [string]$ServerEntry
    )
    @{
        '__APP__'          = $App.AppId
        '__NAME__'         = $Name
        '__PORT__'         = $Port
        '__SERVER_NAME__'  = $ServerName
        '__BASE_PATH__'    = $BasePath
        '__PREFIX__'       = $Prefix
        '__USER__'         = $User
        '__NODE__'         = $Node
        '__SERVER_ENTRY__' = $ServerEntry
    }
}

function Get-NvkNginxExtra {
    param(
        [Parameter(Mandatory)]$App,
        [Parameter(Mandatory)][string]$Kind,
        [Parameter(Mandatory)][hashtable]$Map
    )
    if (-not $App.NginxExtra) { return '' }
    $frag = Join-Path $script:NvkKitRoot "templates/nginx/extras/$($App.NginxExtra)-$Kind.conf"
    if (-not (Test-Path -LiteralPath $frag)) { return '' }
    Expand-NvkPlaceholders (Get-Content -LiteralPath $frag -Raw) $Map
}

function ConvertFrom-NvkNginxTemplate {
    param(
        [Parameter(Mandatory)][string]$TemplatePath,
        [Parameter(Mandatory)][string]$ExtraKind,
        [Parameter(Mandatory)]$App,
        [Parameter(Mandatory)][hashtable]$Map
    )
    $extra = Get-NvkNginxExtra -App $App -Kind $ExtraKind -Map $Map
    $extraLines = @()
    if ($extra.Trim()) {
        $extraLines = $extra -split '\r?\n'
    }
    $rendered = Expand-NvkPlaceholders (Get-Content -LiteralPath $TemplatePath -Raw) $Map
    $out = [System.Collections.Generic.List[string]]::new()
    foreach ($line in ($rendered -split '\r?\n')) {
        if ($line -match '__NGINX_EXTRA__') {
            foreach ($el in $extraLines) { $out.Add($el) }
            continue
        }
        $out.Add($line)
    }
    ($out -join "`n").TrimEnd() + "`n"
}

function Initialize-NvkHttpIncludes {
    $conf = '/etc/nginx/nginx.conf'
    if (-not (Test-Path -LiteralPath $conf)) {
        Write-NvkError "nginx.conf not found at $conf"
    }
    $text = Get-Content -LiteralPath $conf -Raw
    if ($text -match 'include\s+.*/(conf\.d|sites-enabled)') {
        return
    }
    Write-NvkInfo "adding include /etc/nginx/conf.d/*.conf; to $conf"
    Copy-Item -LiteralPath $conf -Destination "$conf.node-vps-kit.bak" -Force
    New-Item -ItemType Directory -Path '/etc/nginx/conf.d' -Force | Out-Null
    $out = [System.Collections.Generic.List[string]]::new()
    $done = $false
    foreach ($line in (Get-Content -LiteralPath "$conf.node-vps-kit.bak")) {
        $out.Add($line)
        if (-not $done -and $line -match '^\s*http\s*\{') {
            $out.Add('    include /etc/nginx/conf.d/*.conf;')
            $done = $true
        }
    }
    Write-NvkFile $conf ($out -join "`n")
}

function Add-NvkNginxIncludeLine {
    param(
        [Parameter(Mandatory)][string]$Site,
        [Parameter(Mandatory)][string]$IncludeLine
    )
    $text = Get-Content -LiteralPath $Site -Raw
    if ($text.Contains($IncludeLine)) {
        Write-NvkInfo "nginx already includes $IncludeLine"
        return
    }
    $serverCount = ([regex]::Matches($text, '(?m)^\s*server\s*\{')).Count
    if ($serverCount -ne 1) {
        Write-Host "nvk: $Site has $serverCount server blocks — add this line inside the right server { } yourself:" -ForegroundColor Yellow
        Write-Host "    $IncludeLine" -ForegroundColor Yellow
        return
    }
    Copy-Item -LiteralPath $Site -Destination "$Site.node-vps-kit.bak" -Force
    $lines = @(Get-Content -LiteralPath $Site)
    $lastBrace = -1
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        if ($lines[$i] -match '^\s*\}\s*$') { $lastBrace = $i; break }
    }
    $new = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($i -eq $lastBrace) { $new.Add("    $IncludeLine") }
        $new.Add($lines[$i])
    }
    Write-NvkFile $Site ($new -join "`n")
    Write-NvkInfo "inserted include into $Site"
}

function Test-NvkNginxConfig {
    Assert-NvkCommand nginx
    Invoke-NvkNative -Command @('nginx', '-t') | Out-Null
}

function Update-NvkNginxService {
    if ((Test-NvkSystemdActive 'nginx')) {
        Invoke-NvkNative -Command @('systemctl', 'reload', 'nginx') | Out-Null
    }
    else {
        Invoke-NvkNative -Command @('systemctl', 'enable', '--now', 'nginx') | Out-Null
    }
    Write-NvkInfo 'nginx reloaded'
}

function Install-NvkNginxSite {
    param(
        [Parameter(Mandatory)]$App,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][hashtable]$Map
    )
    $rendered = ConvertFrom-NvkNginxTemplate `
        -TemplatePath (Join-Path $script:NvkKitRoot 'templates/nginx/site.conf') `
        -ExtraKind 'root' -App $App -Map $Map
    if (Test-Path -LiteralPath '/etc/nginx/sites-available') {
        $dest = "/etc/nginx/sites-available/$($App.AppId)-$Name"
        Write-NvkFile $dest $rendered
        New-Item -ItemType Directory -Path '/etc/nginx/sites-enabled' -Force | Out-Null
        Invoke-NvkNative -Command @('ln', '-sfn', $dest, "/etc/nginx/sites-enabled/$($App.AppId)-$Name") | Out-Null
        Write-NvkInfo "wrote $dest and enabled it"
    }
    else {
        New-Item -ItemType Directory -Path '/etc/nginx/conf.d' -Force | Out-Null
        $dest = "/etc/nginx/conf.d/$($App.AppId)-$Name.conf"
        Write-NvkFile $dest $rendered
        Write-NvkInfo "wrote $dest"
    }
}

function Install-NvkNginxPathMount {
    param(
        [Parameter(Mandatory)]$App,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$NginxSite,
        [Parameter(Mandatory)][hashtable]$Map
    )
    if (-not (Test-Path -LiteralPath $NginxSite)) {
        Write-NvkError "nginx site file not found: $NginxSite"
    }
    New-Item -ItemType Directory -Path '/etc/nginx/snippets' -Force | Out-Null
    $dest = "/etc/nginx/snippets/$($App.AppId)-$Name.conf"
    $rendered = ConvertFrom-NvkNginxTemplate `
        -TemplatePath (Join-Path $script:NvkKitRoot 'templates/nginx/location.conf') `
        -ExtraKind 'path' -App $App -Map $Map
    Write-NvkFile $dest $rendered
    Write-NvkInfo "wrote $dest"
    Add-NvkNginxIncludeLine -Site $NginxSite -IncludeLine "include /etc/nginx/snippets/$($App.AppId)-$Name.conf;"
}

function Write-NvkEnvFile {
    param(
        [Parameter(Mandatory)]$App,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Instance,
        [Parameter(Mandatory)][string]$Data,
        [Parameter(Mandatory)][int]$Port,
        [string]$BasePath
    )
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('NODE_ENV=production')
    $lines.Add("PORT=$Port")
    $lines.Add("$($App.EnvPrefix)_DATA=$Data")
    if ($App.HasSeed) {
        $lines.Add("$($App.EnvPrefix)_SEED=$Instance/current/seed")
    }
    if ($App.HasBasePath) {
        $lines.Add("$($App.EnvPrefix)_BASE_PATH=$BasePath")
    }
    foreach ($extra in @($App.EnvExtra)) {
        if ($null -ne $extra -and $extra -ne '') { $lines.Add($extra) }
    }
    Write-NvkFile $Path ($lines -join "`n")
}

function Update-NvkEnvSeed {
    param(
        [Parameter(Mandatory)]$App,
        [Parameter(Mandatory)][string]$EnvFile,
        [Parameter(Mandatory)][string]$Instance
    )
    if (-not $App.HasSeed) { return }
    if (-not (Test-Path -LiteralPath $EnvFile)) { return }
    $key = "$($App.EnvPrefix)_SEED="
    $lines = @(Get-Content -LiteralPath $EnvFile)
    $found = $false
    $new = foreach ($line in $lines) {
        if ($line -like "$key*") {
            $found = $true
            "$key$Instance/current/seed"
        }
        else {
            $line
        }
    }
    if ($found) {
        Write-NvkFile $EnvFile ($new -join "`n")
    }
}

function Get-NvkEnvValue {
    param(
        [Parameter(Mandatory)][string]$EnvFile,
        [Parameter(Mandatory)][string]$Key
    )
    if (-not (Test-Path -LiteralPath $EnvFile)) { return $null }
    $prefix = "$Key="
    foreach ($line in Get-Content -LiteralPath $EnvFile) {
        if ($line -like "$prefix*") {
            return $line.Substring($prefix.Length)
        }
    }
    $null
}

function Write-NvkSystemdUnit {
    param(
        [Parameter(Mandatory)]$App,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Prefix,
        [Parameter(Mandatory)][string]$User,
        [Parameter(Mandatory)][string]$Node
    )
    $src = Join-Path $script:NvkKitRoot 'templates/app.service'
    if (-not (Test-Path -LiteralPath $src)) {
        Write-NvkError "missing $src"
    }
    $map = Get-NvkPlaceholderMap -App $App -Name $Name -Prefix $Prefix -User $User -Node $Node -ServerEntry $App.ServerEntry -Port '' -ServerName '' -BasePath ''
    $text = Expand-NvkPlaceholders (Get-Content -LiteralPath $src -Raw) $map
    $dest = Get-NvkUnitPath $App.AppId $Name
    Write-NvkFile $dest $text
    $dest
}

function Get-NvkUnitPath {
    param(
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$Name
    )
    "/etc/systemd/system/${AppId}-${Name}.service"
}

function Get-NvkServiceName {
    param(
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$Name
    )
    "$AppId-$Name"
}

function Test-NvkSystemdActive {
    param([Parameter(Mandatory)][string]$Unit)
    $code = Invoke-NvkNative -AllowFailure -Command @('systemctl', 'is-active', '--quiet', $Unit)
    $code -eq 0
}

function Get-NvkSystemdActiveState {
    param([Parameter(Mandatory)][string]$Unit)
    if (-not (Test-NvkCommandExists 'systemctl')) { return $null }
    $prev = $PSNativeCommandUseErrorActionPreference
    try {
        $global:PSNativeCommandUseErrorActionPreference = $false
        $raw = @(& systemctl show -p ActiveState --value $Unit 2>$null) | Select-Object -First 1
        if ($LASTEXITCODE -ne 0 -or -not $raw) { return $null }
        $state = ([string]$raw).Trim()
        if ($state -like 'ActiveState=*') { $state = $state.Substring('ActiveState='.Length).Trim() }
        if (-not $state) { return $null }
        $state
    }
    finally {
        $global:PSNativeCommandUseErrorActionPreference = $prev
    }
}

function Test-NvkSystemdEnabled {
    param([Parameter(Mandatory)][string]$Unit)
    $code = Invoke-NvkNative -AllowFailure -Command @('systemctl', 'is-enabled', '--quiet', $Unit)
    $code -eq 0
}

function Show-NvkServiceJournal {
    param([Parameter(Mandatory)][string]$Service)
    Invoke-NvkNative -AllowFailure -Command @('journalctl', '-u', $Service, '-n', '40', '--no-pager') | Out-Null
}

function Start-NvkSystemdService {
    param([Parameter(Mandatory)][string]$Service)
    Invoke-NvkNative -Command @('systemctl', 'daemon-reload') | Out-Null
    Invoke-NvkNative -Command @('systemctl', 'enable', '--now', $Service) | Out-Null
    Start-Sleep -Seconds 1
    if (-not (Test-NvkSystemdActive $Service)) {
        Show-NvkServiceJournal $Service
        Write-NvkError "service $Service failed to start"
    }
    Write-NvkInfo "started $Service"
}

function Restart-NvkSystemdService {
    param([Parameter(Mandatory)][string]$Service)
    Invoke-NvkNative -Command @('systemctl', 'restart', $Service) | Out-Null
    Start-Sleep -Seconds 1
    if (-not (Test-NvkSystemdActive $Service)) {
        Show-NvkServiceJournal $Service
        Write-NvkError "service $Service failed after update"
    }
}

function Get-NvkUnitUser {
    param([Parameter(Mandatory)][string]$UnitPath)
    if (-not (Test-Path -LiteralPath $UnitPath)) { return $null }
    foreach ($line in Get-Content -LiteralPath $UnitPath) {
        if ($line -like 'User=*') { return $line.Substring(5) }
    }
    $null
}

function Invoke-NvkHealthCheck {
    param(
        [Parameter(Mandatory)]$App,
        [Parameter(Mandatory)][int]$Port,
        [string]$BasePath
    )
    $health = if ($BasePath) {
        "http://127.0.0.1:$Port/$BasePath/$($App.HealthPath)"
    }
    else {
        "http://127.0.0.1:$Port/$($App.HealthPath)"
    }
    try {
        $resp = Invoke-WebRequest -Uri $health -UseBasicParsing -TimeoutSec 5
        $code = [int]$resp.StatusCode
    }
    catch {
        $code = 0
        if ($_.Exception.Response) {
            $code = [int]$_.Exception.Response.StatusCode
        }
    }
    if ($code -ne 200) {
        $shown = if ($code) { $code } else { 'none' }
        Write-NvkInfo "warning: $health returned HTTP $shown (service may still be starting)"
    }
    else {
        Write-NvkInfo "health check ok ($health)"
    }
}

function Backup-NvkInstanceData {
    param(
        [Parameter(Mandatory)][string]$Data,
        [Parameter(Mandatory)][string]$BackupDir
    )
    if (-not (Test-Path -LiteralPath $Data)) {
        Write-NvkError "data directory missing: $Data"
    }
    New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    $name = [datetime]::UtcNow.ToString('yyyy-MM-ddTHHmmss') + 'Z.zip'
    $dest = Join-Path $BackupDir $name
    $partial = "$dest.partial"
    Write-NvkInfo "backing up data to $dest"
    try {
        if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory($Data, $partial)
        Move-Item -LiteralPath $partial -Destination $dest -Force
    }
    catch {
        if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force -ErrorAction SilentlyContinue }
        Write-NvkError "data backup failed — update aborted ($($_.Exception.Message))"
    }
    $dest
}

function Get-NvkCurrentTag {
    param([Parameter(Mandatory)][string]$Instance)
    $versionFile = Join-Path $Instance 'current/VERSION'
    if (Test-Path -LiteralPath $versionFile) {
        return (Get-Content -LiteralPath $versionFile -Raw).Trim()
    }
    $current = Join-Path $Instance 'current'
    if (Test-Path -LiteralPath $current) {
        $item = Get-Item -LiteralPath $current
        if ($item.LinkType) {
            return [IO.Path]::GetFileName($item.Target.TrimEnd('/', '\'))
        }
        return $item.Name
    }
    $null
}

function Invoke-NvkPostUpdateHook {
    param(
        [Parameter(Mandatory)]$App,
        [Parameter(Mandatory)][string]$Instance,
        [Parameter(Mandatory)][string]$Data,
        [Parameter(Mandatory)][string]$Backup,
        [Parameter(Mandatory)][string]$Tag,
        [Parameter(Mandatory)][string]$RunUser
    )
    $hook = Join-Path $Instance 'current/deploy/post-update.sh'
    if (-not (Test-Path -LiteralPath $hook)) { return }
    Invoke-NvkNative -Command @('chmod', '+x', $hook) | Out-Null
    Write-NvkInfo 'running post-update hook'
    $parts = [System.Collections.Generic.List[string]]::new()
    $parts.Add("$($App.EnvPrefix)_DATA=$Data")
    $parts.Add("$($App.EnvPrefix)_BACKUP=$Backup")
    if ($App.HasSeed) {
        $parts.Add("$($App.EnvPrefix)_SEED=$Instance/current/seed")
    }
    $parts.Add($hook)
    $cmd = $parts -join ' '
    $ok = 1
    $idOk = Invoke-NvkNative -AllowFailure -Quiet -Command @('id', $RunUser)
    if ($idOk -eq 0) {
        $ok = Invoke-NvkNative -AllowFailure -Command @('su', '-s', '/bin/sh', '-c', $cmd, $RunUser)
    }
    else {
        $ok = Invoke-NvkNative -AllowFailure -Command @('sh', '-c', $cmd)
    }
    if ($ok -ne 0) {
        Write-NvkError "post-update.sh failed — current still points at $Tag; previous tree is in $Instance/releases"
    }
}

function Remove-NvkOldReleases {
    param(
        [Parameter(Mandatory)][string]$Releases,
        [Parameter(Mandatory)][string[]]$Keep
    )
    if (-not (Test-Path -LiteralPath $Releases)) { return }
    $keepSet = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($k in $Keep) {
        if ($k) { [void]$keepSet.Add($k) }
    }
    Get-ChildItem -LiteralPath $Releases -Directory | ForEach-Object {
        if (-not $keepSet.Contains($_.Name)) {
            Write-NvkInfo "removing old release $($_.Name)"
            Remove-Item -LiteralPath $_.FullName -Recurse -Force
        }
    }
}

function New-NvkChoice {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)]$Value
    )
    [pscustomobject]@{ Label = $Label; Value = $Value }
}

function Test-NvkInteractive {
    if ($env:NVK_INTERACTIVE -eq '0') { return $false }
    if ($env:NVK_INTERACTIVE -eq '1') { return $true }
    try {
        if ([Console]::IsInputRedirected) { return $false }
    }
    catch {
        return $false
    }
    [bool][Environment]::UserInteractive
}

function Resolve-NvkMenuSelection {
    param(
        [string]$Text,
        [AllowEmptyCollection()][object[]]$Choices = @(),
        [switch]$AllowCustom
    )
    if ($null -eq $Text) { return $null }
    $raw = $Text.Trim()
    if ($raw -eq '') { return $null }
    $list = @($Choices)
    $n = $list.Count

    $parsed = 0
    if ([int]::TryParse($raw, [Globalization.NumberStyles]::Integer, [cultureinfo]::InvariantCulture, [ref]$parsed)) {
        if ($parsed -ge 1 -and $parsed -le $n) {
            return $list[$parsed - 1]
        }
        if ($AllowCustom) {
            return (New-NvkChoice -Label $raw -Value $raw)
        }
        return $null
    }

    if ($raw -match '^[A-Za-z]$') {
        $i = [int][char]($raw.ToLowerInvariant()[0]) - [int][char]'a'
        if ($i -ge 0 -and $i -lt $n -and $i -lt 26) {
            return $list[$i]
        }
        return $null
    }

    $exact = @($list | Where-Object { [string]$_.Value -eq $raw -or $_.Label -eq $raw })
    if ($exact.Count -eq 1) { return $exact[0] }

    $prefix = @($list | Where-Object { [string]$_.Value -like "$raw*" -or $_.Label -like "$raw*" })
    if ($prefix.Count -eq 1) { return $prefix[0] }

    if ($AllowCustom) {
        return (New-NvkChoice -Label $raw -Value $raw)
    }
    $null
}

function Read-NvkChoice {
    param(
        [Parameter(Mandatory)][string]$Message,
        [AllowEmptyCollection()][object[]]$Choices = @(),
        [switch]$AllowCustom,
        [string]$MissingError
    )
    $list = @($Choices)
    if ($list.Count -eq 0 -and -not $AllowCustom) {
        Write-NvkError $(if ($MissingError) { $MissingError } else { $Message })
    }
    if (-not (Test-NvkInteractive)) {
        Write-NvkError $(if ($MissingError) { $MissingError } else { $Message })
    }
    if ($list.Count -eq 1 -and -not $AllowCustom) {
        Write-NvkInfo "using $($list[0].Label)"
        return $list[0].Value
    }

    Write-Host ''
    Write-NvkInfo $Message
    $letterHint = ''
    if ($list.Count -gt 0) {
        $lastLetter = [char]([int][char]'a' + [Math]::Min($list.Count, 26) - 1)
        $letterHint = ", a-$lastLetter"
        for ($i = 0; $i -lt $list.Count; $i++) {
            Write-Host ('  {0}) {1}' -f ($i + 1), $list[$i].Label)
        }
    }
    $customHint = if ($AllowCustom -and $list.Count -gt 0) { ', or type a value' } else { '' }
    $range = if ($list.Count -gt 0) { "1-$($list.Count)$letterHint" } else { 'a value' }
    while ($true) {
        $answer = $null
        try {
            $answer = Read-Host "$($script:NvkCmd): choose $range$customHint"
        }
        catch {
            Write-NvkError 'no input (need a terminal, or pass the flags)'
        }
        $picked = Resolve-NvkMenuSelection -Text $answer -Choices $list -AllowCustom:$AllowCustom
        if ($picked) { return $picked.Value }
        Write-Host "$($script:NvkCmd): not a valid choice" -ForegroundColor Yellow
    }
}

function Get-NvkFqdn {
    if (Test-NvkCommandExists 'hostname') {
        $prev = $PSNativeCommandUseErrorActionPreference
        try {
            $global:PSNativeCommandUseErrorActionPreference = $false
            $fqdn = @(& hostname -f 2>$null) | Select-Object -First 1
            if ($LASTEXITCODE -eq 0 -and $fqdn) {
                $text = ([string]$fqdn).Trim()
                if ($text) { return $text }
            }
        }
        finally {
            $global:PSNativeCommandUseErrorActionPreference = $prev
        }
    }
    [System.Net.Dns]::GetHostName()
}

function Get-NvkListeningPorts {
    $ports = [System.Collections.Generic.HashSet[int]]::new()
    if (-not (Test-NvkCommandExists 'ss')) { return $ports }
    $prev = $PSNativeCommandUseErrorActionPreference
    try {
        $global:PSNativeCommandUseErrorActionPreference = $false
        $lines = @(& ss -lnt 2>$null)
        if ($LASTEXITCODE -ne 0) { return $ports }
        foreach ($line in $lines) {
            if ($line -match ':(\d+)\s+\S+\s*$') {
                [void]$ports.Add([int]$Matches[1])
            }
        }
    }
    finally {
        $global:PSNativeCommandUseErrorActionPreference = $prev
    }
    $ports
}

function Get-NvkUsedPortSet {
    $ports = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($row in @(Get-NvkStartup)) {
        $envFile = Join-Path $row.Instance 'env'
        $value = Get-NvkEnvValue $envFile 'PORT'
        $parsed = 0
        if ($value -and [int]::TryParse($value, [Globalization.NumberStyles]::Integer, [cultureinfo]::InvariantCulture, [ref]$parsed) -and $parsed -ge 1) {
            [void]$ports.Add($parsed)
        }
    }
    foreach ($p in Get-NvkListeningPorts) {
        [void]$ports.Add($p)
    }
    ,$ports
}

function Get-NvkSuggestedPorts {
    param(
        [int]$Count = 3,
        [int]$Start = 3000
    )
    $used = Get-NvkUsedPortSet
    $out = [System.Collections.Generic.List[int]]::new()
    $p = $Start
    while ($out.Count -lt $Count -and $p -le 65535) {
        if (-not $used.Contains($p)) { $out.Add($p) }
        $p++
    }
    $out
}

function Get-NvkNginxSiteFiles {
    $files = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $specs = @(
        @{ Path = '/etc/nginx/sites-enabled'; Filter = '*' }
        @{ Path = '/etc/nginx/sites-available'; Filter = '*' }
        @{ Path = '/etc/nginx/conf.d'; Filter = '*.conf' }
    )
    foreach ($spec in $specs) {
        if (-not (Test-Path -LiteralPath $spec.Path)) { continue }
        Get-ChildItem -LiteralPath $spec.Path -File -Filter $spec.Filter -ErrorAction SilentlyContinue | ForEach-Object {
            $full = $_.FullName
            $key = $full
            try { $key = (Resolve-Path -LiteralPath $full).Path } catch { $key = $full }
            if ($seen.Add($key)) { $files.Add($full) }
        }
    }
    @($files)
}

function Resolve-NvkAppIdParam {
    param([string]$AppId)
    if (-not [string]::IsNullOrWhiteSpace($AppId)) {
        return $AppId.Trim()
    }
    $ids = @(Get-NvkFamilyAppIds)
    if ($ids.Count -eq 0) {
        Write-NvkError '-App is required (no app profiles in this kit). If this is a new app, run nvk-update to fetch profiles.'
    }
    $choices = @($ids | ForEach-Object { New-NvkChoice -Label $_ -Value $_ })
    $available = $ids -join ' '
    Read-NvkChoice `
        -Message '-App is required. Select an app.' `
        -Choices $choices `
        -MissingError "-App is required. Available: $available"
}

function Resolve-NvkInstanceNameParam {
    param(
        [Parameter(Mandatory)][string]$AppId,
        [string]$Name,
        [Parameter(Mandatory)][ValidateSet('New', 'Existing')][string]$For
    )
    if (-not [string]::IsNullOrWhiteSpace($Name)) {
        Assert-NvkName $Name
        return $Name
    }

    $rows = @(Get-NvkStartup -AppId $AppId)
    $taken = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($row in $rows) { [void]$taken.Add($row.Name) }

    if ($For -eq 'Existing') {
        $names = @(
            $rows |
                Where-Object { Test-Path -LiteralPath (Join-Path $_.Instance 'env') } |
                ForEach-Object { $_.Name } |
                Sort-Object -Unique
        )
        if ($names.Count -eq 0) {
            Write-NvkError "-Name is required (no installed instances of $AppId)"
        }
        $choices = @($names | ForEach-Object { New-NvkChoice -Label $_ -Value $_ })
        return (Read-NvkChoice `
                -Message "-Name is required. Select a $AppId instance." `
                -Choices $choices `
                -MissingError "-Name is required. Instances: $($names -join ' ')")
    }

    $suggestions = [System.Collections.Generic.List[string]]::new()
    foreach ($candidate in @('www', 'test')) {
        if (-not $taken.Contains($candidate)) { $suggestions.Add($candidate) }
    }
    $choices = @($suggestions | ForEach-Object { New-NvkChoice -Label $_ -Value $_ })
    while ($true) {
        $picked = Read-NvkChoice `
            -Message '-Name is required. Select one, or type a new instance name.' `
            -Choices $choices `
            -AllowCustom `
            -MissingError '-Name is required'
        $picked = [string]$picked
        if (-not (Test-NvkName $picked)) {
            if (-not (Test-NvkInteractive)) {
                Write-NvkError '-Name must be letters, digits, hyphen, or underscore'
            }
            Write-Host "$($script:NvkCmd): -Name must be letters, digits, hyphen, or underscore" -ForegroundColor Yellow
            continue
        }
        if ($taken.Contains($picked)) {
            if (-not (Test-NvkInteractive)) {
                Write-NvkError "instance '$picked' already exists (use nvk-app-update -App $AppId -Name $picked)"
            }
            Write-Host "$($script:NvkCmd): instance '$picked' already exists" -ForegroundColor Yellow
            continue
        }
        return $picked
    }
}

function Resolve-NvkPortParam {
    param([int]$Port)
    if ($Port -ne 0) {
        Assert-NvkPort $Port
        return $Port
    }
    $used = Get-NvkUsedPortSet
    $choices = [System.Collections.Generic.List[object]]::new()
    foreach ($p in (Get-NvkSuggestedPorts)) {
        $choices.Add((New-NvkChoice -Label "$p" -Value $p))
    }
    while ($true) {
        $picked = Read-NvkChoice `
            -Message '-Port is required. Select a free port, or type one.' `
            -Choices $choices `
            -AllowCustom `
            -MissingError '-Port is required'
        $parsed = 0
        if (-not [int]::TryParse([string]$picked, [Globalization.NumberStyles]::Integer, [cultureinfo]::InvariantCulture, [ref]$parsed)) {
            if (-not (Test-NvkInteractive)) { Write-NvkError '-Port must be an integer' }
            Write-Host "$($script:NvkCmd): -Port must be an integer" -ForegroundColor Yellow
            continue
        }
        if ($parsed -lt 1 -or $parsed -gt 65535) {
            if (-not (Test-NvkInteractive)) { Write-NvkError '-Port out of range' }
            Write-Host "$($script:NvkCmd): -Port out of range" -ForegroundColor Yellow
            continue
        }
        if ($used.Contains($parsed)) {
            if (-not (Test-NvkInteractive)) { Write-NvkError "-Port $parsed is already in use" }
            Write-Host "$($script:NvkCmd): port $parsed is already in use" -ForegroundColor Yellow
            continue
        }
        return $parsed
    }
}

function Resolve-NvkNginxInstallParams {
    param(
        [Parameter(Mandatory)]$App,
        [string]$ServerName,
        [string]$NginxSite,
        [string]$BasePath,
        [switch]$SkipNginx,
        [string]$InstanceName
    )
    $server = if ($ServerName) { $ServerName.Trim() } else { '' }
    $site = if ($NginxSite) { $NginxSite.Trim() } else { '' }
    $path = if ($BasePath) { $BasePath.Trim('/') } else { '' }

    if (-not $App.HasBasePath -and ($site -or $path)) {
        Write-NvkError "$($App.AppId) installs at a dedicated hostname only; omit -NginxSite and -BasePath"
    }

    if ($SkipNginx) {
        return [pscustomobject]@{
            ServerName = ''
            NginxSite  = ''
            BasePath   = ''
            SkipNginx  = $true
        }
    }
    if ($server -and $site) {
        Write-NvkError 'use either -ServerName (new site) or -NginxSite (path mount), not both'
    }
    if ($server -and $path) {
        Write-NvkError '-ServerName installs the app at /; omit -BasePath (use -NginxSite for /name/)'
    }

    if (-not $server -and -not $site) {
        $modeChoices = [System.Collections.Generic.List[object]]::new()
        $modeChoices.Add((New-NvkChoice -Label 'dedicated hostname (new site)' -Value 'hostname'))
        if ($App.HasBasePath) {
            $modeChoices.Add((New-NvkChoice -Label 'path on an existing site' -Value 'path'))
        }
        $modeChoices.Add((New-NvkChoice -Label 'skip nginx' -Value 'skip'))
        $modeMissing = if ($App.HasBasePath) {
            'provide -ServerName HOST or -NginxSite FILE (or -SkipNginx)'
        }
        else {
            "provide -ServerName HOST ($($App.AppId) installs at a dedicated hostname only) or -SkipNginx"
        }
        $mode = Read-NvkChoice `
            -Message 'How should nginx expose this instance?' `
            -Choices @($modeChoices) `
            -MissingError $modeMissing
        if ($mode -eq 'skip') {
            return [pscustomobject]@{
                ServerName = ''
                NginxSite  = ''
                BasePath   = ''
                SkipNginx  = $true
            }
        }
        if ($mode -eq 'hostname') {
            $hostChoices = [System.Collections.Generic.List[object]]::new()
            $fqdn = Get-NvkFqdn
            if ($fqdn) {
                $hostChoices.Add((New-NvkChoice -Label $fqdn -Value $fqdn))
                if ($fqdn -notlike 'www.*') {
                    $hostChoices.Add((New-NvkChoice -Label "www.$fqdn" -Value "www.$fqdn"))
                }
            }
            $server = [string](Read-NvkChoice `
                    -Message '-ServerName is required. Select a hostname, or type one.' `
                    -Choices @($hostChoices) `
                    -AllowCustom `
                    -MissingError 'provide -ServerName HOST or -NginxSite FILE (or -SkipNginx)')
            $server = $server.Trim()
            if (-not $server) {
                Write-NvkError '-ServerName is required'
            }
        }
        else {
            $sites = @(Get-NvkNginxSiteFiles)
            $siteChoices = @($sites | ForEach-Object { New-NvkChoice -Label $_ -Value $_ })
            $site = [string](Read-NvkChoice `
                    -Message '-NginxSite is required. Select a site file, or type a path.' `
                    -Choices $siteChoices `
                    -AllowCustom `
                    -MissingError '-NginxSite requires a site file path')
            $site = $site.Trim()
        }
    }

    if ($site -and -not $path) {
        $pathChoices = [System.Collections.Generic.List[object]]::new()
        if ($InstanceName -and (Test-NvkName $InstanceName)) {
            $pathChoices.Add((New-NvkChoice -Label $InstanceName -Value $InstanceName))
        }
        $path = [string](Read-NvkChoice `
                -Message '-BasePath is required for a path mount. Select one, or type a URL prefix (no leading slash).' `
                -Choices @($pathChoices) `
                -AllowCustom `
                -MissingError '-NginxSite requires -BasePath (path mounts need a URL prefix)')
        $path = $path.Trim('/')
        if (-not $path) {
            Write-NvkError '-NginxSite requires -BasePath (path mounts need a URL prefix)'
        }
    }

    [pscustomobject]@{
        ServerName = $server
        NginxSite  = $site
        BasePath   = $path
        SkipNginx  = $false
    }
}

function Resolve-NvkStartupAction {
    Read-NvkChoice `
        -Message 'Add or remove the boot unit?' `
        -Choices @(
            (New-NvkChoice -Label 'add' -Value 'Add')
            (New-NvkChoice -Label 'remove' -Value 'Remove')
        ) `
        -MissingError 'pass -Add or -Remove'
}

function Resolve-NvkStartupTarget {
    param(
        [string]$AppId,
        [string]$Name,
        [Parameter(Mandatory)][ValidateSet('Add', 'Remove')][string]$Action
    )
    $app = if ($AppId) { $AppId.Trim() } else { '' }
    $inst = if ($Name) { $Name.Trim() } else { '' }
    if ($inst) { Assert-NvkName $inst }

    if ($app -and $inst) {
        return [pscustomobject]@{ AppId = $app; Name = $inst }
    }

    $rows = @(Get-NvkStartup)
    if ($Action -eq 'Remove') {
        $rows = @($rows | Where-Object { $_.Present })
    }
    else {
        $rows = @(
            $rows |
                Where-Object { -not $_.Present } |
                Where-Object { Test-Path -LiteralPath (Join-Path $_.Instance 'env') }
        )
    }
    if ($app) { $rows = @($rows | Where-Object { $_.App -eq $app }) }
    if ($inst) { $rows = @($rows | Where-Object { $_.Name -eq $inst }) }

    if ($rows.Count -eq 0) {
        $need = if (-not $app -and -not $inst) { '-App and -Name are required' } elseif (-not $app) { '-App is required' } else { '-Name is required' }
        Write-NvkError "$need (no instances available to $($Action.ToLowerInvariant()))"
    }

    $choices = @(
        $rows | Sort-Object App, Name | ForEach-Object {
            New-NvkChoice -Label "$($_.App) / $($_.Name)" -Value $_
        }
    )
    $picked = Read-NvkChoice `
        -Message "-$Action needs an instance. Select one." `
        -Choices $choices `
        -MissingError "-App and -Name are required for -$Action"
    [pscustomobject]@{ AppId = $picked.App; Name = $picked.Name }
}

function Invoke-NvkStartupAction {
    param(
        [Parameter(Mandatory)][ValidateSet('Add', 'Remove')][string]$Action,
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$Name
    )
    if ($Action -eq 'Remove') {
        Remove-NvkStartup -AppId $AppId -Name $Name
    }
    else {
        Add-NvkStartup -AppId $AppId -Name $Name
    }
}

function Install-NvkAppInstance {
    param(
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][int]$Port,
        [string]$ServerName,
        [string]$NginxSite,
        [string]$BasePath,
        [string]$Prefix,
        [string]$Repo,
        [string]$Version = 'latest',
        [string]$Archive,
        [string]$User,
        [switch]$SkipNginx
    )
    Assert-NvkRoot
    Assert-NvkName $Name
    Assert-NvkPort $Port
    $app = Import-NvkApp $AppId
    if ($Prefix) { $app.Prefix = $Prefix }
    if ($User) { $app.User = $User }
    if ($Repo) { $app.Repo = $Repo }

    $BasePath = if ($BasePath) { $BasePath.Trim('/') } else { '' }

    if (-not $app.HasBasePath -and ($NginxSite -or $BasePath)) {
        Write-NvkError "$($app.AppId) installs at a dedicated hostname only; omit -NginxSite and -BasePath"
    }

    if (-not $SkipNginx) {
        if ($ServerName -and $NginxSite) {
            Write-NvkError 'use either -ServerName (new site) or -NginxSite (path mount), not both'
        }
        if (-not $ServerName -and -not $NginxSite) {
            if ($app.HasBasePath) {
                Write-NvkError 'provide -ServerName HOST or -NginxSite FILE (or -SkipNginx)'
            }
            Write-NvkError "provide -ServerName HOST ($($app.AppId) installs at a dedicated hostname only) or -SkipNginx"
        }
        if ($NginxSite -and -not $BasePath) {
            Write-NvkError '-NginxSite requires -BasePath (path mounts need a URL prefix)'
        }
        if ($ServerName -and $BasePath) {
            Write-NvkError '-ServerName installs the app at /; omit -BasePath (use -NginxSite for /name/)'
        }
    }

    Assert-NvkCommand tar
    Assert-NvkCommand systemctl
    if (-not $SkipNginx) { Assert-NvkCommand nginx }
    Assert-NvkNodeVersion $app.NodeMajor
    $node = Get-NvkNodePath

    $instance = Join-Path $app.Prefix $Name
    $releases = Join-Path $instance 'releases'
    $data = Join-Path $instance 'data'
    $envFile = Join-Path $instance 'env'
    $service = Get-NvkServiceName $app.AppId $Name

    if ((Test-Path -LiteralPath (Join-Path $instance 'current')) -and (Test-Path -LiteralPath $envFile)) {
        Write-NvkError "instance '$Name' already exists at $instance (use nvk-app-update -App $($app.AppId) -Name $Name)"
    }

    $tag = Resolve-NvkReleaseTag -Repo $app.Repo -AppId $app.AppId -Version $Version
    Write-NvkInfo "release $tag → $instance"

    $archivePath = Resolve-NvkAppArchive -App $app -Tag $tag -Archive $Archive
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("nvk-unpack-" + [guid]::NewGuid().ToString('n'))
    try {
        $unpacked = Expand-NvkAppArchive -Archive $archivePath -Destination $tmp -App $app
        $fromVersion = Get-NvkVersionFromRelease $unpacked
        if ($fromVersion) { $tag = $fromVersion }

        New-Item -ItemType Directory -Path $releases, $data -Force | Out-Null
        $relDir = Join-Path $releases $tag
        if (Test-Path -LiteralPath $relDir) { Remove-Item -LiteralPath $relDir -Recurse -Force }
        Invoke-NvkNative -Command @('mv', $unpacked, $relDir) | Out-Null
        Repair-NvkUnixExecuteBits $relDir
        Set-NvkCurrentSymlink $relDir (Join-Path $instance 'current')
    }
    finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }

    Initialize-NvkSystemUser -User $app.User -Home $app.Prefix
    if (-not (Test-Path -LiteralPath $envFile)) {
        Write-NvkEnvFile -App $app -Path $envFile -Instance $instance -Data $data -Port $Port -BasePath $BasePath
        Write-NvkInfo "wrote $envFile"
    }
    Set-NvkOwner -User $app.User -Path @($instance)

    Write-NvkSystemdUnit -App $app -Name $Name -Prefix $app.Prefix -User $app.User -Node $node | Out-Null
    Start-NvkSystemdService $service

    if (-not $SkipNginx) {
        Initialize-NvkHttpIncludes
        $map = Get-NvkPlaceholderMap -App $app -Name $Name -Port "$Port" -ServerName $ServerName -BasePath $BasePath -Prefix $app.Prefix -User $app.User -Node $node -ServerEntry $app.ServerEntry
        if ($ServerName) {
            Install-NvkNginxSite -App $app -Name $Name -Map $map
        }
        else {
            Install-NvkNginxPathMount -App $app -Name $Name -NginxSite $NginxSite -Map $map
        }
        Test-NvkNginxConfig
        Update-NvkNginxService
    }

    Invoke-NvkHealthCheck -App $app -Port $Port -BasePath $BasePath

    $hostHint = if ($ServerName) { $ServerName } else { 'your.domain' }
    Write-Host @"

Instance '$Name' ($($app.AppId)) is installed.

  App:      $instance/current  ($tag)
  Data:     $data
  Env:      $envFile
  Service:  systemctl status $service
  Logs:     journalctl -u $service -f

Next:
  - Point DNS for this host at this VPS (A / AAAA).
  - Open ports 80 and 443 on the firewall.
  - After DNS works: sudo certbot --nginx -d $hostHint
  - Later upgrades: sudo nvk-app-update -App $($app.AppId) -Name $Name
  - Remove it: sudo nvk-app-uninstall -App $($app.AppId) -Name $Name

"@
    if ($app.PostInstallNote) {
        Write-Host $app.PostInstallNote
    }
}

function Update-NvkAppInstance {
    param(
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$Name,
        [string]$Prefix,
        [string]$Repo,
        [string]$Version = 'latest',
        [string]$Archive
    )
    Assert-NvkRoot
    Assert-NvkName $Name
    $app = Import-NvkApp $AppId
    if ($Prefix) { $app.Prefix = $Prefix }
    if ($Repo) { $app.Repo = $Repo }

    $instance = Join-Path $app.Prefix $Name
    $envFile = Join-Path $instance 'env'
    $releases = Join-Path $instance 'releases'
    $service = Get-NvkServiceName $app.AppId $Name
    $unitPath = Get-NvkUnitPath $app.AppId $Name

    if (-not (Test-Path -LiteralPath $instance)) {
        Write-NvkError "instance not found: $instance (install first)"
    }
    if (-not (Test-Path -LiteralPath $envFile)) {
        Write-NvkError "missing $envFile"
    }
    $current = Join-Path $instance 'current'
    if (-not (Test-Path -LiteralPath $current)) {
        Write-NvkError "missing $current"
    }
    if (-not (Test-Path -LiteralPath $unitPath)) {
        Write-NvkError "no systemd unit $unitPath — re-add with: nvk-startup -Add -App $($app.AppId) -Name $Name"
    }

    Assert-NvkCommand tar
    Assert-NvkCommand systemctl

    $data = Get-NvkEnvValue $envFile "$($app.EnvPrefix)_DATA"
    if (-not $data) { $data = Join-Path $instance 'data' }
    $backup = Get-NvkEnvValue $envFile "$($app.EnvPrefix)_BACKUP"
    if (-not $backup) { $backup = Join-Path $instance 'backup' }

    $runUser = $app.User
    $fromUnit = Get-NvkUnitUser $unitPath
    if ($fromUnit) { $runUser = $fromUnit }

    $tag = Resolve-NvkReleaseTag -Repo $app.Repo -AppId $app.AppId -Version $Version
    $prev = Get-NvkCurrentTag $instance
    if ($prev -eq $tag -and -not $Archive) {
        Write-NvkInfo "already on $tag — nothing to do"
        return
    }

    Write-NvkInfo "upgrading ${Name}: $(if ($prev) { $prev } else { 'unknown' }) → $tag"
    Backup-NvkInstanceData -Data $data -BackupDir $backup | Out-Null
    $idOk = Invoke-NvkNative -AllowFailure -Quiet -Command @('id', $runUser)
    if ($idOk -eq 0) {
        Set-NvkOwner -User $runUser -Path @($backup)
    }

    $archivePath = Resolve-NvkAppArchive -App $app -Tag $tag -Archive $Archive
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("nvk-unpack-" + [guid]::NewGuid().ToString('n'))
    try {
        $unpacked = Expand-NvkAppArchive -Archive $archivePath -Destination $tmp -App $app
        $fromVersion = Get-NvkVersionFromRelease $unpacked
        if ($fromVersion) { $tag = $fromVersion }
        New-Item -ItemType Directory -Path $releases -Force | Out-Null
        $relDir = Join-Path $releases $tag
        if (Test-Path -LiteralPath $relDir) { Remove-Item -LiteralPath $relDir -Recurse -Force }
        Invoke-NvkNative -Command @('mv', $unpacked, $relDir) | Out-Null
        Repair-NvkUnixExecuteBits $relDir
        Update-NvkEnvSeed -App $app -EnvFile $envFile -Instance $instance
        Set-NvkCurrentSymlink $relDir $current
        if ($idOk -eq 0) {
            Set-NvkOwner -User $runUser -Path @($relDir, $current)
        }
    }
    finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
    }

    Invoke-NvkPostUpdateHook -App $app -Instance $instance -Data $data -Backup $backup -Tag $tag -RunUser $runUser
    Restart-NvkSystemdService $service
    Remove-NvkOldReleases -Releases $releases -Keep @($tag, $prev)
    Write-NvkInfo "updated $Name to $tag (data untouched: $data)"
    Write-NvkInfo "status: systemctl status $service"
}

function Test-NvkFileOrLink {
    param([Parameter(Mandatory)][string]$Path)
    if (Test-Path -LiteralPath $Path) { return $true }
    $parent = Split-Path -Parent $Path
    $leaf = Split-Path -Leaf $Path
    if (-not $parent -or -not (Test-Path -LiteralPath $parent)) { return $false }
    foreach ($item in @(Get-ChildItem -LiteralPath $parent -Force -ErrorAction SilentlyContinue)) {
        if ($item.Name -eq $leaf) { return $true }
    }
    $false
}

function Test-NvkNginxSnippetIncludeLine {
    param(
        # Blank lines are normal in nginx configs. A mandatory [string] rejects ""
        # and would abort uninstall while scanning sites that are not this instance.
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Line,
        [Parameter(Mandatory)][string]$SnippetName
    )
    if ([string]::IsNullOrWhiteSpace($Line)) { return $false }
    $pattern = '^\s*include\s+["'']?(?:\S*/)?snippets/' + [regex]::Escape($SnippetName) + '["'']?\s*;\s*(?:#.*)?$'
    [bool]($Line -match $pattern)
}

function Get-NvkInstanceDirFromUnit {
    param(
        [Parameter(Mandatory)][string]$UnitPath,
        [Parameter(Mandatory)][string]$Name
    )
    if (-not (Test-Path -LiteralPath $UnitPath)) { return $null }
    $envDir = $null
    $workDir = $null
    foreach ($line in @(Get-Content -LiteralPath $UnitPath)) {
        if ($line -like 'EnvironmentFile=*') {
            $value = $line.Substring('EnvironmentFile='.Length).Trim().Trim('"').Trim("'")
            if ($value.StartsWith('-')) { $value = $value.Substring(1).Trim() }
            if ($value) {
                $parent = Split-Path -Parent $value
                if ($parent) { $envDir = $parent }
            }
        }
        elseif ($line -like 'WorkingDirectory=*') {
            $value = $line.Substring('WorkingDirectory='.Length).Trim().Trim('"').Trim("'")
            $suffix = "/$Name/current"
            if ($value.EndsWith($suffix)) {
                $workDir = $value.Substring(0, $value.Length - '/current'.Length)
            }
        }
    }
    if ($envDir) { return $envDir }
    $workDir
}

function ConvertTo-NvkLexicalPath {
    param([Parameter(Mandatory)][string]$Path)
    $rooted = $Path.StartsWith('/') -or $Path.StartsWith('\')
    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($part in ($Path.Replace('\', '/') -split '/')) {
        if ($part -eq '' -or $part -eq '.') { continue }
        if ($part -eq '..') {
            if ($parts.Count -gt 0) { $parts.RemoveAt($parts.Count - 1) }
            continue
        }
        $parts.Add($part)
    }
    if (-not $rooted) {
        return ($parts -join '/')
    }
    if ($parts.Count -eq 0) { return '/' }
    '/' + ($parts -join '/')
}

function Assert-NvkDeletableInstanceDir {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )
    $leaf = [System.IO.Path]::GetFileName($Path)
    if ($leaf -ne $Name) {
        Write-NvkError "refusing to delete '$Path' (directory name is not '$Name')"
    }
    $parent = Split-Path -Parent $Path
    if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $Path) {
        Write-NvkError "refusing to delete '$Path'"
    }
    $parent = $parent.TrimEnd('/', '\')
    $blocked = @(
        '/', '/opt', '/etc', '/usr', '/usr/local', '/var', '/home', '/root',
        '/bin', '/sbin', '/lib', '/lib64', '/boot', '/dev', '/proc', '/sys', '/run', '/tmp',
        '/private/tmp', '/private/var', '/private/etc'
    )
    foreach ($b in $blocked) {
        if ($Path -eq $b -or $parent -eq $b) {
            Write-NvkError "refusing to delete '$Path'"
        }
    }
}

function Resolve-NvkDeletableInstanceDir {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )
    if (-not [System.IO.Path]::IsPathRooted($Path)) {
        Write-NvkError "refusing to delete relative path '$Path'"
    }
    $lexical = ConvertTo-NvkLexicalPath $Path
    Assert-NvkDeletableInstanceDir -Path $lexical -Name $Name
    if (-not (Test-Path -LiteralPath $lexical)) {
        return $lexical
    }
    $item = Get-Item -LiteralPath $lexical -Force
    if ($item.LinkType) {
        Write-NvkError "refusing to delete '$lexical' (it is a symlink)"
    }
    $resolved = ConvertTo-NvkLexicalPath ((Resolve-Path -LiteralPath $lexical).Path)
    Assert-NvkDeletableInstanceDir -Path $resolved -Name $Name
    $resolved
}

function Resolve-NvkUninstallInstanceDir {
    param(
        [Parameter(Mandatory)]$App,
        [Parameter(Mandatory)][string]$Name,
        [string]$Prefix
    )
    $raw = $null
    if ($Prefix) {
        $raw = Join-Path $Prefix $Name
    }
    else {
        $fromUnit = Get-NvkInstanceDirFromUnit -UnitPath (Get-NvkUnitPath $App.AppId $Name) -Name $Name
        if ($fromUnit) {
            $raw = $fromUnit
        }
        else {
            $raw = Join-Path $App.Prefix $Name
        }
    }
    Resolve-NvkDeletableInstanceDir -Path $raw -Name $Name
}

function Get-NvkPathsOutsideInstance {
    param(
        [Parameter(Mandatory)]$App,
        [Parameter(Mandatory)][string]$InstanceDir
    )
    $found = [System.Collections.Generic.List[string]]::new()
    $envFile = Join-Path $InstanceDir 'env'
    if (-not (Test-Path -LiteralPath $envFile)) {
        return ,$found
    }
    $root = [System.IO.Path]::GetFullPath($InstanceDir).TrimEnd('/', '\')
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($key in @("$($App.EnvPrefix)_DATA", "$($App.EnvPrefix)_BACKUP")) {
        $value = Get-NvkEnvValue $envFile $key
        if (-not $value) { continue }
        if (-not [System.IO.Path]::IsPathRooted($value)) { continue }
        $full = [System.IO.Path]::GetFullPath($value).TrimEnd('/', '\')
        $inside = ($full -eq $root) -or $full.StartsWith($root + '/') -or $full.StartsWith($root + '\')
        if ($inside) { continue }
        $shown = ConvertTo-NvkLexicalPath $value
        if ($seen.Add($shown)) { $found.Add($shown) }
    }
    ,$found
}

function Get-NvkNginxManagedPaths {
    param(
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$Name
    )
    $stem = "$AppId-$Name"
    @(
        "/etc/nginx/sites-enabled/$stem"
        "/etc/nginx/sites-available/$stem"
        "/etc/nginx/conf.d/$stem.conf"
        "/etc/nginx/snippets/$stem.conf"
    )
}

function Get-NvkInstanceNginxPlan {
    param(
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$Name
    )
    $stem = "$AppId-$Name"
    $snippetName = "$stem.conf"
    $managed = @(Get-NvkNginxManagedPaths -AppId $AppId -Name $Name)
    $files = [System.Collections.Generic.List[string]]::new()
    $skip = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($path in $managed) {
        [void]$skip.Add($path)
        if (Test-NvkFileOrLink $path) {
            $files.Add($path)
            if (Test-Path -LiteralPath $path) {
                try { [void]$skip.Add((Resolve-Path -LiteralPath $path).Path) } catch { }
            }
        }
    }

    $candidates = [System.Collections.Generic.List[string]]::new()
    foreach ($site in @(Get-NvkNginxSiteFiles)) { $candidates.Add($site) }
    $nginxConf = '/etc/nginx/nginx.conf'
    if (Test-Path -LiteralPath $nginxConf) { $candidates.Add($nginxConf) }

    $includeFiles = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($site in $candidates) {
        if ($skip.Contains($site)) { continue }
        $key = $site
        if (Test-Path -LiteralPath $site) {
            try { $key = (Resolve-Path -LiteralPath $site).Path } catch { $key = $site }
        }
        if ($skip.Contains($key)) { continue }
        if (-not $seen.Add($key)) { continue }
        if (-not (Test-Path -LiteralPath $site)) { continue }
        $hit = $false
        foreach ($line in @(Get-Content -LiteralPath $site)) {
            if (Test-NvkNginxSnippetIncludeLine -Line $line -SnippetName $snippetName) {
                $hit = $true
                break
            }
        }
        if ($hit) { $includeFiles.Add($site) }
    }

    [pscustomobject]@{
        Files        = $files
        IncludeFiles = $includeFiles
        SnippetName  = $snippetName
    }
}

function Remove-NvkSnippetIncludeFromFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$SnippetName
    )
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    $kept = [System.Collections.Generic.List[string]]::new()
    $removed = $false
    foreach ($line in @(Get-Content -LiteralPath $Path)) {
        if (Test-NvkNginxSnippetIncludeLine -Line $line -SnippetName $SnippetName) {
            $removed = $true
            continue
        }
        $kept.Add($line)
    }
    if ($removed) {
        Write-NvkFile $Path ($kept -join "`n")
        Write-NvkInfo "removed nginx include from $Path"
    }
    $removed
}

function Remove-NvkInstanceNginx {
    param(
        [Parameter(Mandatory)]$Plan
    )
    $changed = $false
    foreach ($site in @($Plan.IncludeFiles)) {
        if (Remove-NvkSnippetIncludeFromFile -Path $site -SnippetName $Plan.SnippetName) {
            $changed = $true
        }
    }
    foreach ($path in @($Plan.Files)) {
        if (Test-NvkFileOrLink $path) {
            Invoke-NvkNative -Quiet -Command @('rm', '-f', '--', $path) | Out-Null
            Write-NvkInfo "removed $path"
            $changed = $true
        }
    }
    if (-not $changed) { return $false }
    if (-not (Test-NvkCommandExists 'nginx')) {
        Write-NvkInfo 'nginx command not found; skipped config test and reload'
        return $true
    }
    try {
        Test-NvkNginxConfig
    }
    catch {
        Write-NvkError 'nginx config test failed; instance directory was left in place. Fix nginx, then re-run uninstall.'
    }
    if ((Test-NvkCommandExists 'systemctl') -and (Test-NvkSystemdActive 'nginx')) {
        Invoke-NvkNative -Command @('systemctl', 'reload', 'nginx') | Out-Null
        Write-NvkInfo 'nginx reloaded'
    }
    else {
        Write-NvkInfo 'nginx config updated (nginx is not running)'
    }
    $true
}

function Assert-NvkInstanceStopped {
    param(
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$Name
    )
    $svc = Get-NvkServiceName $AppId $Name
    $state = Get-NvkSystemdActiveState $svc
    $running = @('active', 'activating', 'deactivating', 'reloading')
    if ($running -contains $state) {
        Write-NvkError "service $svc is $state. Stop it first: nvk-service -Stop -App $AppId -Name $Name"
    }
}

function Remove-NvkInstanceSystemd {
    param(
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$Name
    )
    $svc = Get-NvkServiceName $AppId $Name
    $unit = Get-NvkUnitPath $AppId $Name
    $dropin = "$unit.d"
    $wants = "/etc/systemd/system/multi-user.target.wants/$svc.service"
    $removed = $false
    if (Test-NvkFileOrLink $unit) {
        Invoke-NvkNative -Quiet -Command @('rm', '-f', '--', $unit) | Out-Null
        Write-NvkInfo "removed $unit"
        $removed = $true
    }
    if (Test-Path -LiteralPath $dropin) {
        Invoke-NvkNative -Quiet -Command @('rm', '-rf', '--', $dropin) | Out-Null
        Write-NvkInfo "removed $dropin"
        $removed = $true
    }
    if (Test-NvkFileOrLink $wants) {
        if (Test-NvkCommandExists 'systemctl') {
            Invoke-NvkNative -AllowFailure -Quiet -DiscardError -Command @('systemctl', 'disable', $svc) | Out-Null
        }
        if (Test-NvkFileOrLink $wants) {
            Invoke-NvkNative -Quiet -Command @('rm', '-f', '--', $wants) | Out-Null
            Write-NvkInfo "removed $wants"
            $removed = $true
        }
    }
    if ($removed -and (Test-NvkCommandExists 'systemctl')) {
        Invoke-NvkNative -Quiet -Command @('systemctl', 'daemon-reload') | Out-Null
        Invoke-NvkNative -AllowFailure -Quiet -DiscardError -Command @('systemctl', 'reset-failed', $svc) | Out-Null
    }
    $removed
}

function Confirm-NvkAppUninstall {
    param(
        [switch]$Yes,
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$InstanceDir,
        [Parameter(Mandatory)][bool]$FolderExists,
        [Parameter(Mandatory)][bool]$UnitExists,
        [Parameter(Mandatory)]$NginxPlan,
        $ExternalPaths
    )
    Write-Host ''
    Write-NvkInfo "this will permanently delete the '$Name' instance of $AppId"
    if ($FolderExists) {
        Write-Host "  folder   $InstanceDir (code, data, backups, env)"
    }
    else {
        Write-Host "  folder   $InstanceDir (already absent)"
    }
    if ($UnitExists) {
        Write-Host "  systemd  $(Get-NvkUnitPath $AppId $Name)"
    }
    foreach ($path in @($NginxPlan.Files)) {
        Write-Host "  nginx    $path"
    }
    foreach ($path in @($NginxPlan.IncludeFiles)) {
        Write-Host "  nginx    include snippets/$($NginxPlan.SnippetName) in $path"
    }
    foreach ($path in @($ExternalPaths)) {
        Write-Host "  left     $path (outside the instance folder)"
    }
    Write-Host ''
    if ($Yes) { return }
    if (-not (Test-NvkInteractive)) {
        Write-NvkError "refusing to delete '$Name' without -Yes"
    }
    while ($true) {
        $answer = $null
        try {
            $answer = Read-Host "$($script:NvkCmd): type '$Name' to uninstall, or press Enter to cancel"
        }
        catch {
            Write-NvkError 'no input (need a terminal, or pass -Yes)'
        }
        if ([string]::IsNullOrWhiteSpace($answer)) {
            Write-NvkError 'cancelled'
        }
        if ($answer.Trim() -eq $Name) { return }
        Write-Host "$($script:NvkCmd): type the instance name '$Name' to confirm" -ForegroundColor Yellow
    }
}

function Uninstall-NvkAppInstance {
    param(
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$Name,
        [string]$Prefix,
        [switch]$Yes
    )
    Assert-NvkRoot
    Assert-NvkName $Name
    $app = Import-NvkApp $AppId
    if (-not (Test-NvkName $app.AppId)) {
        Write-NvkError "app id '$($app.AppId)' is not a safe path name"
    }
    $instanceDir = Resolve-NvkUninstallInstanceDir -App $app -Name $Name -Prefix $Prefix
    $unit = Get-NvkUnitPath $app.AppId $Name
    $unitExists = Test-NvkFileOrLink $unit
    $folderExists = Test-Path -LiteralPath $instanceDir
    $nginxPlan = Get-NvkInstanceNginxPlan -AppId $app.AppId -Name $Name
    $external = Get-NvkPathsOutsideInstance -App $app -InstanceDir $instanceDir
    $nginxCount = @($nginxPlan.Files).Count + @($nginxPlan.IncludeFiles).Count
    if (-not $folderExists -and -not $unitExists -and $nginxCount -eq 0) {
        Write-NvkError "instance '$Name' not found at $instanceDir (no systemd unit or nginx config either)"
    }

    Assert-NvkInstanceStopped -AppId $app.AppId -Name $Name
    Confirm-NvkAppUninstall `
        -Yes:$Yes `
        -AppId $app.AppId `
        -Name $Name `
        -InstanceDir $instanceDir `
        -FolderExists $folderExists `
        -UnitExists $unitExists `
        -NginxPlan $nginxPlan `
        -ExternalPaths $external

    $service = Get-NvkServiceName $app.AppId $Name
    # Re-check after the prompt. Uninstall never stops a service.
    Assert-NvkInstanceStopped -AppId $app.AppId -Name $Name
    $removedNginx = Remove-NvkInstanceNginx -Plan $nginxPlan

    $removedFolder = $false
    Assert-NvkInstanceStopped -AppId $app.AppId -Name $Name
    if (Test-Path -LiteralPath $instanceDir) {
        $instanceDir = Resolve-NvkDeletableInstanceDir -Path $instanceDir -Name $Name
        Invoke-NvkNative -Command @('rm', '-rf', '--', $instanceDir) | Out-Null
        if (Test-Path -LiteralPath $instanceDir) {
            Write-NvkError "failed to delete $instanceDir"
        }
        Write-NvkInfo "removed $instanceDir"
        $removedFolder = $true
    }

    $removedUnit = Remove-NvkInstanceSystemd -AppId $app.AppId -Name $Name

    $userLeft = ''
    $idOk = Invoke-NvkNative -AllowFailure -Quiet -DiscardError -Command @('id', $app.User)
    if ($idOk -eq 0) { $userLeft = $app.User }

    Write-Host @"

Uninstalled '$Name' ($($app.AppId)).

  Folder:   $(if ($removedFolder) { $instanceDir } else { '(already absent)' })
  Service:  $(if ($removedUnit) { $service } else { '(no unit)' })
  Nginx:    $(if ($removedNginx) { 'removed' } else { '(none found)' })
"@
    if ($userLeft) {
        Write-Host "  User:     $userLeft is still on this box"
    }
    foreach ($path in @($external)) {
        Write-Host "  Left:     $path"
    }
    if ($removedNginx) {
        Write-Host '  TLS certificates under /etc/letsencrypt, if any, are still on this box.'
    }
    Write-Host ''
}

function Get-NvkStartup {
    param(
        [string]$AppId,
        [string]$Name
    )
    $rows = [System.Collections.Generic.List[object]]::new()
    $appIds = if ($AppId) { @($AppId) } else { @(Get-NvkFamilyAppIds) }
    foreach ($id in $appIds) {
        $app = $null
        try { $app = Import-NvkApp $id } catch { continue }
        $instanceNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        if (Test-Path -LiteralPath $app.Prefix) {
            Get-ChildItem -LiteralPath $app.Prefix -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                if (Test-Path -LiteralPath (Join-Path $_.FullName 'env')) {
                    [void]$instanceNames.Add($_.Name)
                }
            }
        }
        $unitGlob = "/etc/systemd/system/$id-*.service"
        Get-ChildItem -Path $unitGlob -ErrorAction SilentlyContinue | ForEach-Object {
            $base = $_.BaseName
            $prefix = "$id-"
            if ($base.StartsWith($prefix)) {
                [void]$instanceNames.Add($base.Substring($prefix.Length))
            }
        }
        foreach ($inst in $instanceNames) {
            if ($Name -and $inst -ne $Name) { continue }
            $unit = Get-NvkUnitPath $id $inst
            $svc = Get-NvkServiceName $id $inst
            $hasUnit = Test-Path -LiteralPath $unit
            $rows.Add([pscustomobject]@{
                    App     = $id
                    Name    = $inst
                    Service = $svc
                    Unit    = $unit
                    Present = $hasUnit
                    Enabled = if ($hasUnit) { Test-NvkSystemdEnabled $svc } else { $false }
                    Active  = if ($hasUnit) { Test-NvkSystemdActive $svc } else { $false }
                    Instance = (Join-Path $app.Prefix $inst)
                })
        }
    }
    $rows
}

function Remove-NvkStartup {
    param(
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$Name
    )
    Assert-NvkRoot
    Assert-NvkName $Name
    $null = Import-NvkApp $AppId
    $svc = Get-NvkServiceName $AppId $Name
    $unit = Get-NvkUnitPath $AppId $Name
    if (-not (Test-Path -LiteralPath $unit)) {
        Write-NvkError "no unit $unit"
    }
    Invoke-NvkNative -AllowFailure -Command @('systemctl', 'stop', $svc) | Out-Null
    Invoke-NvkNative -AllowFailure -Command @('systemctl', 'disable', $svc) | Out-Null
    Remove-Item -LiteralPath $unit -Force
    Invoke-NvkNative -Command @('systemctl', 'daemon-reload') | Out-Null
    Write-NvkInfo "removed unit $svc (instance files and nginx left in place)"
}

function Add-NvkStartup {
    param(
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$Name
    )
    Assert-NvkRoot
    Assert-NvkName $Name
    $app = Import-NvkApp $AppId
    $instance = Join-Path $app.Prefix $Name
    $envFile = Join-Path $instance 'env'
    $current = Join-Path $instance 'current'
    if (-not (Test-Path -LiteralPath $instance) -or -not (Test-Path -LiteralPath $envFile)) {
        Write-NvkError "instance not found at $instance (install first)"
    }
    if (-not (Test-Path -LiteralPath $current)) {
        Write-NvkError "missing $current"
    }
    Assert-NvkNodeVersion $app.NodeMajor
    $node = Get-NvkNodePath
    $runUser = $app.User
    $unitPath = Get-NvkUnitPath $app.AppId $Name
    $fromUnit = Get-NvkUnitUser $unitPath
    if ($fromUnit) { $runUser = $fromUnit }
    $idOk = Invoke-NvkNative -AllowFailure -Quiet -Command @('id', $runUser)
    if ($idOk -ne 0) {
        Initialize-NvkSystemUser -User $runUser -Home $app.Prefix
    }
    Write-NvkSystemdUnit -App $app -Name $Name -Prefix $app.Prefix -User $runUser -Node $node | Out-Null
    $svc = Get-NvkServiceName $app.AppId $Name
    Start-NvkSystemdService $svc
}

function Write-NvkStartupTable {
    param($Rows)
    $list = @($Rows)
    if ($list.Count -eq 0) {
        Write-NvkInfo 'no kit-managed instances found'
        return
    }
    $list | Select-Object App, Name, Service, Present, Enabled, Active, Instance |
        Format-Table -AutoSize | Out-String | Write-Host
}

function Get-NvkServiceRows {
    param(
        [string]$AppId,
        [string]$Name
    )
    @(Get-NvkStartup -AppId $AppId -Name $Name | Where-Object { $_.Present })
}

function Write-NvkServiceTable {
    param($Rows)
    $list = @($Rows)
    if ($list.Count -eq 0) {
        Write-NvkInfo 'no systemd units for kit instances (install an app, or nvk-startup -Add)'
        return
    }
    $list | Sort-Object App, Name | ForEach-Object {
        [pscustomobject]@{
            App     = $_.App
            Name    = $_.Name
            Service = $_.Service
            State   = if ($_.Active) { 'running' } else { 'stopped' }
        }
    } | Format-Table -AutoSize | Out-String | Write-Host
}

function Resolve-NvkServiceAction {
    Read-NvkChoice `
        -Message 'Start, stop, or restart the service?' `
        -Choices @(
            (New-NvkChoice -Label 'start' -Value 'Start')
            (New-NvkChoice -Label 'stop' -Value 'Stop')
            (New-NvkChoice -Label 'restart' -Value 'Restart')
        ) `
        -MissingError 'pass -Start, -Stop, or -Restart'
}

function Resolve-NvkServiceTarget {
    param(
        [string]$AppId,
        [string]$Name,
        [Parameter(Mandatory)][ValidateSet('Start', 'Stop', 'Restart')][string]$Action
    )
    $app = if ($AppId) { $AppId.Trim() } else { '' }
    $inst = if ($Name) { $Name.Trim() } else { '' }
    if ($inst) { Assert-NvkName $inst }

    if ($app -and $inst) {
        return [pscustomobject]@{ AppId = $app; Name = $inst }
    }

    $rows = @(Get-NvkServiceRows -AppId $app -Name $inst)
    if ($rows.Count -eq 0) {
        $need = if (-not $app -and -not $inst) { '-App and -Name are required' } elseif (-not $app) { '-App is required' } else { '-Name is required' }
        Write-NvkError "$need (no systemd units to $($Action.ToLowerInvariant()))"
    }

    $choices = @(
        $rows | Sort-Object App, Name | ForEach-Object {
            $state = if ($_.Active) { 'running' } else { 'stopped' }
            New-NvkChoice -Label "$($_.App) / $($_.Name) ($state)" -Value $_
        }
    )
    $picked = Read-NvkChoice `
        -Message "-$Action needs an instance. Select one." `
        -Choices $choices `
        -MissingError "-App and -Name are required for -$Action"
    [pscustomobject]@{ AppId = $picked.App; Name = $picked.Name }
}

function Invoke-NvkServiceAction {
    param(
        [Parameter(Mandatory)][ValidateSet('Start', 'Stop', 'Restart')][string]$Action,
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$Name
    )
    Assert-NvkRoot
    Assert-NvkName $Name
    $null = Import-NvkApp $AppId
    Assert-NvkCommand systemctl
    $svc = Get-NvkServiceName $AppId $Name
    $unit = Get-NvkUnitPath $AppId $Name
    if (-not (Test-Path -LiteralPath $unit)) {
        Write-NvkError "no systemd unit $unit — add it with: nvk-startup -Add -App $AppId -Name $Name"
    }
    $verb = $Action.ToLowerInvariant()
    Invoke-NvkNative -Command @('systemctl', $verb, $svc) | Out-Null
    if ($Action -ne 'Stop') {
        Start-Sleep -Seconds 1
    }
    $active = Test-NvkSystemdActive $svc
    if ($Action -eq 'Stop') {
        if ($active) {
            Show-NvkServiceJournal $svc
            Write-NvkError "service $svc failed to stop"
        }
        Write-NvkInfo "stopped $svc"
        return
    }
    if (-not $active) {
        Show-NvkServiceJournal $svc
        $why = if ($Action -eq 'Restart') { 'failed to restart' } else { 'failed to start' }
        Write-NvkError "service $svc $why"
    }
    $word = if ($Action -eq 'Restart') { 'restarted' } else { 'started' }
    Write-NvkInfo "$word $svc"
}
