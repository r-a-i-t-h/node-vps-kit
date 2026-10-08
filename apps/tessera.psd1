@{
    AppId           = 'tessera'
    Repo            = 'r-a-i-t-h/tessera'
    Tarball         = 'tessera.tar.gz'
    Prefix          = '/opt/tessera'
    User            = 'tessera'
    NodeMajor       = 20
    ArchiveRoot     = 'tessera'
    ServerEntry     = 'dist/server.js'
    EnvPrefix       = 'TESSERA'
    HealthPath      = 'health'
    HasSeed         = $true
    HasBasePath     = $false
    NginxExtra      = 'upload-limit'
    EnvExtra        = @(
        'TESSERA_SECURE_COOKIES=1'
    )
    PostInstallNote = 'Seed login (change it): admin / admin'
}
