@{
    AppId           = 'proseden'
    Repo            = 'r-a-i-t-h/proseden'
    Tarball         = 'proseden.tar.gz'
    Prefix          = '/opt/proseden'
    User            = 'proseden'
    NodeMajor       = 20
    ArchiveRoot     = 'proseden'
    ServerEntry     = 'dist/server.js'
    EnvPrefix       = 'PROSEDEN'
    HealthPath      = 'health'
    HasSeed         = $true
    HasBasePath     = $true
    NginxExtra      = 'live-events'
    EnvExtra        = @(
        'PROSEDEN_SECURE_COOKIES=1'
        'PROSEDEN_MANAGERS='
    )
    PostInstallNote = 'Seed login (change it): admin / admin'
}
