[CmdletBinding()]
param(
    [switch]$KeepRunning,
    [switch]$SkipRestart,
    [switch]$Fresh,
    [string]$ProjectName = "musicflow",
    [ValidateRange(1024, 65535)][int]$AdminPort = 8081,
    [ValidateRange(1024, 65535)][int]$GatewayPort = 8082,
    [string]$AdminUsername = "musicflow-admin"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$composeFile = Join-Path $projectRoot "compose.yaml"
$envFile = Join-Path $projectRoot ".env"
$configureAdminScript = Join-Path $PSScriptRoot "configure-identity-admin.ps1"
$bootstrapPasswordFile = Join-Path $projectRoot ".secrets\keycloak-bootstrap-admin-password"
$verifierSecretFile = Join-Path $projectRoot ".secrets\keycloak-verifier-client-secret"
$adminUsername = $AdminUsername.Trim()
$bootstrapUsername = "temp-admin"
$verifierClientId = "musicflow-identity-verifier"
$previousAdminPort = $env:KEYCLOAK_ADMIN_PORT
$previousGatewayPort = $env:KEYCLOAK_GATEWAY_PORT
$previousHostnameUrl = $env:KEYCLOAK_HOSTNAME_URL

if ($Fresh) {
    if ($KeepRunning) {
        throw "-Fresh y -KeepRunning no pueden utilizarse juntos."
    }
    if (-not $PSBoundParameters.ContainsKey("ProjectName")) {
        $ProjectName = "musicflow-identity-verify"
    }
    if (-not $PSBoundParameters.ContainsKey("AdminPort")) {
        $AdminPort = 18081
    }
    if (-not $PSBoundParameters.ContainsKey("GatewayPort")) {
        $GatewayPort = 18082
    }

    if ($ProjectName -notmatch '^musicflow-identity-verify(?:-[a-z0-9-]+)?$') {
        throw "-Fresh solo admite proyectos temporales con prefijo musicflow-identity-verify."
    }
}

if ($AdminPort -eq $GatewayPort) {
    throw "AdminPort y GatewayPort deben ser diferentes."
}
if ([string]::IsNullOrWhiteSpace($adminUsername)) {
    throw "AdminUsername no puede estar vacio."
}

$env:KEYCLOAK_ADMIN_PORT = [string]$AdminPort
$env:KEYCLOAK_GATEWAY_PORT = [string]$GatewayPort
$env:KEYCLOAK_HOSTNAME_URL = "http://127.0.0.1:$AdminPort"

$expectedIssuer = "http://127.0.0.1:$AdminPort/realms/musicflow"
$adminBaseUrl = "http://127.0.0.1:$AdminPort"
$gatewayBaseUrl = "http://127.0.0.1:$GatewayPort"

function Resolve-DockerExecutable {
    $dockerCommand = Get-Command docker -ErrorAction SilentlyContinue
    if ($dockerCommand) {
        return $dockerCommand.Source
    }

    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Programs\DockerDesktop\resources\bin\docker.exe"),
        (Join-Path $env:ProgramFiles "Docker\Docker\resources\bin\docker.exe")
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    throw "No se encontro docker.exe. Confirma que Docker Desktop este instalado y accesible."
}

function Invoke-Compose {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

    & $script:dockerExecutable compose `
        --project-name $script:ProjectName `
        --env-file $script:envFile `
        --file $script:composeFile `
        --profile identity `
        @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "docker compose termino con codigo $LASTEXITCODE."
    }
}

function Get-HttpStatusCode {
    param([Parameter(Mandatory = $true)][string]$Uri)

    try {
        $response = Invoke-WebRequest `
            -Uri $Uri `
            -MaximumRedirection 0 `
            -TimeoutSec 10 `
            -UseBasicParsing
        return [int]$response.StatusCode
    }
    catch {
        $responseProperty = $_.Exception.PSObject.Properties["Response"]
        if ($responseProperty -and $responseProperty.Value) {
            return [int]$responseProperty.Value.StatusCode
        }

        throw
    }
}

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)]$Actual,
        [Parameter(Mandatory = $true)]$Expected,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if ($Actual -ne $Expected) {
        throw "$Message Esperado: '$Expected'. Obtenido: '$Actual'."
    }
}

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Get-VerifierHeaders {
    $verifierSecret = (Get-Content -LiteralPath $script:verifierSecretFile -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($verifierSecret)) {
        throw "El secreto del verificador esta vacio."
    }

    try {
        $tokenResponse = Invoke-RestMethod `
            -Method Post `
            -Uri "$script:adminBaseUrl/realms/master/protocol/openid-connect/token" `
            -ContentType "application/x-www-form-urlencoded" `
            -Body @{
                client_id     = $script:verifierClientId
                client_secret = $verifierSecret
                grant_type    = "client_credentials"
            } `
            -TimeoutSec 10

        Assert-True `
            -Condition (-not [string]::IsNullOrWhiteSpace($tokenResponse.access_token)) `
            -Message "Keycloak no entrego un token al verificador local."

        return @{ Authorization = "Bearer $($tokenResponse.access_token)" }
    }
    finally {
        $verifierSecret = $null
    }
}

function Assert-BootstrapAdminRemoved {
    $bootstrapPassword = (Get-Content -LiteralPath $script:bootstrapPasswordFile -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($bootstrapPassword)) {
        throw "El secreto bootstrap esta vacio."
    }

    try {
        try {
            Invoke-RestMethod `
                -Method Post `
                -Uri "$script:adminBaseUrl/realms/master/protocol/openid-connect/token" `
                -ContentType "application/x-www-form-urlencoded" `
                -Body @{
                    client_id  = "admin-cli"
                    grant_type = "password"
                    username   = $script:bootstrapUsername
                    password   = $bootstrapPassword
                } `
                -TimeoutSec 10 | Out-Null
        }
        catch {
            $statusCode = if ($_.Exception.Response) {
                [int]$_.Exception.Response.StatusCode
            }
            else {
                0
            }

            if ($statusCode -eq 400 -or $statusCode -eq 401) {
                return
            }

            throw
        }

        throw "La cuenta administrativa bootstrap todavia puede autenticarse."
    }
    finally {
        $bootstrapPassword = $null
    }
}

function Test-IdentityContract {
    $discovery = Invoke-RestMethod `
        -Uri "$script:gatewayBaseUrl/realms/musicflow/.well-known/openid-configuration" `
        -TimeoutSec 10

    Assert-Equal $discovery.issuer $script:expectedIssuer "El issuer no coincide."
    Assert-True `
        -Condition ([bool]($discovery.code_challenge_methods_supported -contains "S256")) `
        -Message "Discovery no anuncia PKCE S256."

    Assert-Equal `
        $discovery.jwks_uri `
        "$script:expectedIssuer/protocol/openid-connect/certs" `
        "Discovery anuncio una ubicacion JWKS inesperada."

    $jwks = Invoke-RestMethod `
        -Uri "$script:gatewayBaseUrl/realms/musicflow/protocol/openid-connect/certs" `
        -TimeoutSec 10
    Assert-True -Condition ($jwks.keys.Count -gt 0) -Message "JWKS no contiene claves de firma."

    Assert-Equal (Get-HttpStatusCode "$script:gatewayBaseUrl/gateway-health") 204 "Gateway no esta sano."

    foreach ($deniedPath in @("/", "/admin/", "/realms/master/", "/health", "/metrics")) {
        Assert-Equal `
            (Get-HttpStatusCode "$script:gatewayBaseUrl$deniedPath") `
            404 `
            "El gateway expuso una ruta denegada: $deniedPath."
    }

    Assert-Equal `
        (Get-HttpStatusCode "$script:adminBaseUrl/admin/master/console/") `
        200 `
        "La consola administrativa local no responde."

    $headers = Get-VerifierHeaders
    try {
        $realm = Invoke-RestMethod `
            -Headers $headers `
            -Uri "$script:adminBaseUrl/admin/realms/musicflow" `
            -TimeoutSec 10

        Assert-Equal $realm.realm "musicflow" "La API administrativa devolvio un realm inesperado."
        Assert-True -Condition ([bool]$realm.bruteForceProtected) -Message "La proteccion de fuerza bruta debe estar habilitada."

        $desktopClientResponse = Invoke-RestMethod `
                -Headers $headers `
                -Uri "$script:adminBaseUrl/admin/realms/musicflow/clients?clientId=musicflow-desktop" `
                -TimeoutSec 10
        $desktopClients = @($desktopClientResponse | ForEach-Object { $_ })

        Assert-Equal $desktopClients.Count 1 "Debe existir exactamente un cliente musicflow-desktop."
        $desktopClient = $desktopClients[0]

        Assert-True -Condition ([bool]$desktopClient.publicClient) -Message "El cliente desktop debe ser publico."
        Assert-True -Condition ([bool]$desktopClient.standardFlowEnabled) -Message "Authorization Code debe estar habilitado."
        Assert-True -Condition (-not [bool]$desktopClient.implicitFlowEnabled) -Message "Implicit Flow debe estar deshabilitado."
        Assert-True -Condition (-not [bool]$desktopClient.directAccessGrantsEnabled) -Message "Direct Access Grants debe estar deshabilitado."
        Assert-True -Condition (-not [bool]$desktopClient.serviceAccountsEnabled) -Message "Service Accounts debe estar deshabilitado."
        Assert-Equal $desktopClient.attributes.'pkce.code.challenge.method' "S256" "PKCE S256 no es obligatorio."
        Assert-True `
            -Condition ([bool]($desktopClient.redirectUris -contains "http://127.0.0.1")) `
            -Message "Falta el callback loopback especial de Keycloak."

        $mapperResponse = Invoke-RestMethod `
                -Headers $headers `
                -Uri "$script:adminBaseUrl/admin/realms/musicflow/clients/$($desktopClient.id)/protocol-mappers/models" `
                -TimeoutSec 10
        $mappers = @($mapperResponse | ForEach-Object { $_ })
        $audienceMapper = @($mappers | Where-Object { $_.name -eq "musicflow-api-audience" })
        Assert-Equal $audienceMapper.Count 1 "Debe existir el mapper de audiencia musicflow-api."
        Assert-Equal `
            $audienceMapper[0].config.'included.client.audience' `
            "musicflow-api" `
            "El mapper no agrega la audiencia esperada."

        $writeStatusCode = 0
        try {
            Invoke-WebRequest `
                -Method Put `
                -Headers $headers `
                -Uri "$script:adminBaseUrl/admin/realms/musicflow" `
                -ContentType "application/json" `
                -Body '{"displayName":"MusicFlow"}' `
                -TimeoutSec 10 `
                -UseBasicParsing | Out-Null
            $writeStatusCode = 200
        }
        catch {
            if ($_.Exception.Response) {
                $writeStatusCode = [int]$_.Exception.Response.StatusCode
            }
            else {
                throw
            }
        }
        Assert-Equal `
            $writeStatusCode `
            403 `
            "El verificador local no debe poder modificar el realm."

        Assert-BootstrapAdminRemoved
    }
    finally {
        $headers = $null
    }
}

if (-not (Test-Path -LiteralPath $envFile)) {
    throw "No existe .env. Copia .env.example y conserva las credenciales locales existentes."
}
if (-not (Test-Path -LiteralPath $bootstrapPasswordFile)) {
    throw "No existe el secreto bootstrap. Ejecuta scripts/initialize-identity-secrets.ps1."
}
if (-not (Test-Path -LiteralPath $verifierSecretFile)) {
    throw "No existe el secreto del verificador. Ejecuta scripts/initialize-identity-secrets.ps1."
}
if (-not (Test-Path -LiteralPath $configureAdminScript)) {
    throw "No existe el script de aprovisionamiento del administrador permanente."
}

$dockerExecutable = Resolve-DockerExecutable

try {
    Push-Location $projectRoot

    Invoke-Compose config --quiet
    $composeConfiguration = (Invoke-Compose config --format json) | ConvertFrom-Json
    $bootstrapUsername = $composeConfiguration.services.keycloak.environment.KC_BOOTSTRAP_ADMIN_USERNAME
    Assert-True `
        -Condition (-not [string]::IsNullOrWhiteSpace($bootstrapUsername)) `
        -Message "Falta KC_BOOTSTRAP_ADMIN_USERNAME."

    $keycloakEnvironmentNames = @(
        $composeConfiguration.services.keycloak.environment.PSObject.Properties.Name
    )
    foreach ($forbiddenVariable in @(
            "KC_DB_PASSWORD",
            "KCRAW_DB_PASSWORD",
            "KC_BOOTSTRAP_ADMIN_PASSWORD",
            "KCRAW_BOOTSTRAP_ADMIN_PASSWORD"
        )) {
        Assert-True `
            -Condition (-not [bool]($keycloakEnvironmentNames -contains $forbiddenVariable)) `
            -Message "El secreto $forbiddenVariable no debe aparecer en el entorno declarado."
    }

    Assert-Equal `
        $composeConfiguration.services.'keycloak-postgres'.environment.POSTGRES_PASSWORD_FILE `
        "/run/secrets/keycloak_db_password" `
        "PostgreSQL de identidad debe leer su contrasena desde un secreto montado."

    Assert-True `
        -Condition (-not ($composeConfiguration.services.'keycloak-postgres'.PSObject.Properties.Name -contains "ports")) `
        -Message "PostgreSQL de identidad no debe publicar puertos."
    Assert-True `
        -Condition ([bool]$composeConfiguration.networks.'identity-backend'.internal) `
        -Message "La red de datos de identidad debe permanecer interna."

    foreach ($serviceName in @("keycloak", "keycloak-gateway")) {
        $service = $composeConfiguration.services.$serviceName
        Assert-Equal $service.ports.Count 1 "$serviceName debe publicar exactamente un puerto."
        Assert-Equal $service.ports[0].host_ip "127.0.0.1" "$serviceName solo debe enlazarse a loopback."
    }

    Invoke-Compose build keycloak
    Invoke-Compose up --detach --wait keycloak-gateway

    if ($Fresh) {
        & $configureAdminScript `
            -AdminPort $AdminPort `
            -BootstrapUsername $bootstrapUsername `
            -AdminUsername $adminUsername
    }

    $keycloakUser = (Invoke-Compose exec --no-TTY keycloak id -u | Select-Object -Last 1).Trim()
    $gatewayUser = (Invoke-Compose exec --no-TTY keycloak-gateway id -u | Select-Object -Last 1).Trim()
    Assert-Equal $keycloakUser "1000" "Keycloak debe ejecutarse como usuario no root."
    Assert-Equal $gatewayUser "101" "El gateway debe ejecutarse como usuario no root."

    Test-IdentityContract

    if (-not $SkipRestart) {
        Invoke-Compose restart keycloak
        Invoke-Compose up --detach --wait keycloak-gateway
        Test-IdentityContract
    }

    Invoke-Compose ps keycloak-postgres keycloak keycloak-gateway
    Write-Host "Identidad verificada correctamente." -ForegroundColor Green
}
finally {
    try {
        if ($dockerExecutable) {
            if ($Fresh) {
                if ($ProjectName -notmatch '^musicflow-identity-verify(?:-[a-z0-9-]+)?$') {
                    throw "Se rechazo la limpieza de un proyecto que no es temporal."
                }
                Invoke-Compose down --volumes --remove-orphans
            }
            elseif (-not $KeepRunning) {
                Invoke-Compose stop keycloak-gateway keycloak keycloak-postgres
            }
        }
    }
    finally {
        $env:KEYCLOAK_ADMIN_PORT = $previousAdminPort
        $env:KEYCLOAK_GATEWAY_PORT = $previousGatewayPort
        $env:KEYCLOAK_HOSTNAME_URL = $previousHostnameUrl
        Pop-Location -ErrorAction SilentlyContinue
    }
}
