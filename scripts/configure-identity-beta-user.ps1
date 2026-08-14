[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)][int]$AdminPort = 8081,
    [ValidatePattern('^[a-z][a-z0-9._-]{2,31}$')][string]$Username = "musicflow-beta",
    [string]$ProjectName = "musicflow"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$composeFile = Join-Path $projectRoot "compose.yaml"
$envFile = Join-Path $projectRoot ".env"
$publicationSecretFile = Join-Path $projectRoot ".secrets\keycloak-publication-admin-client-secret"
$userPasswordFile = Join-Path $projectRoot ".secrets\keycloak-beta-user-password"
$adminBaseUrl = "http://127.0.0.1:$AdminPort"
$temporaryClientId = "musicflow-beta-provisioner"
$dockerExecutable = $null
$temporaryClientCreated = $false
$gatewayStarted = $false
$userCreated = $false
$temporaryToken = $null
$previousProxySubnet = $env:KEYCLOAK_PROXY_SUBNET

function Resolve-DockerExecutable {
    $dockerCommand = Get-Command docker -ErrorAction SilentlyContinue
    if ($dockerCommand) {
        return $dockerCommand.Source
    }

    foreach ($candidate in @(
            (Join-Path $env:LOCALAPPDATA "Programs\DockerDesktop\resources\bin\docker.exe"),
            (Join-Path $env:ProgramFiles "Docker\Docker\resources\bin\docker.exe")
        )) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    throw "No se encontro docker.exe. Confirma que Docker Desktop este activo."
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

function Read-Secret {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "No existe el secreto requerido. Ejecuta initialize-identity-secrets.ps1."
    }

    $value = (Get-Content -LiteralPath $Path -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Un secreto requerido esta vacio."
    }

    return $value
}

function Get-ProvisionerToken {
    param([Parameter(Mandatory = $true)][string]$ClientSecret)

    $response = Invoke-RestMethod `
        -Method Post `
        -Uri "$script:adminBaseUrl/realms/master/protocol/openid-connect/token" `
        -ContentType "application/x-www-form-urlencoded" `
        -Body @{
            client_id     = $script:temporaryClientId
            client_secret = $ClientSecret
            grant_type    = "client_credentials"
        } `
        -TimeoutSec 10

    if ([string]::IsNullOrWhiteSpace($response.access_token)) {
        throw "Keycloak no entrego el token administrativo temporal."
    }

    return $response.access_token
}

function Get-ExactBetaUser {
    param([Parameter(Mandatory = $true)][hashtable]$Headers)

    $encodedUsername = [Uri]::EscapeDataString($script:Username)
    $response = Invoke-RestMethod `
        -Headers $Headers `
        -Uri "$script:adminBaseUrl/admin/realms/musicflow/users?username=$encodedUsername&exact=true" `
        -TimeoutSec 10
    $users = @($response | ForEach-Object { $_ })

    if ($users.Count -gt 1) {
        throw "Existe mas de un usuario beta con el nombre exacto indicado."
    }
    if ($users.Count -eq 1) {
        return $users[0]
    }

    return $null
}

function Remove-TemporaryClient {
    param([Parameter(Mandatory = $true)][hashtable]$Headers)

    $clientsResponse = Invoke-RestMethod `
        -Headers $Headers `
        -Uri "$script:adminBaseUrl/admin/realms/master/clients?clientId=$script:temporaryClientId" `
        -TimeoutSec 10
    $clients = @($clientsResponse | ForEach-Object { $_ })

    if ($clients.Count -gt 1) {
        throw "Existe mas de un aprovisionador administrativo temporal."
    }
    if ($clients.Count -eq 1) {
        Invoke-RestMethod `
            -Method Delete `
            -Headers $Headers `
            -Uri "$script:adminBaseUrl/admin/realms/master/clients/$($clients[0].id)" `
            -TimeoutSec 10 | Out-Null
    }
}

if ($ProjectName -notmatch '^musicflow(?:-[a-z0-9-]+)?$') {
    throw "ProjectName debe pertenecer a un proyecto MusicFlow controlado."
}
if (-not (Test-Path -LiteralPath $envFile)) {
    throw "No existe .env. Conserva la configuracion local antes de aprovisionar identidad."
}

$publicationSecret = Read-Secret -Path $publicationSecretFile
$userPassword = Read-Secret -Path $userPasswordFile
$dockerExecutable = Resolve-DockerExecutable
$envFileContent = Get-Content -LiteralPath $envFile
$proxySubnetLine = @(
    $envFileContent | Where-Object { $_ -match '^\s*KEYCLOAK_PROXY_SUBNET\s*=' }
) | Select-Object -Last 1
if ([string]::IsNullOrWhiteSpace($env:KEYCLOAK_PROXY_SUBNET) -and $proxySubnetLine) {
    $env:KEYCLOAK_PROXY_SUBNET = ($proxySubnetLine -split '=', 2)[1].Trim()
}

$bootstrapCommand = @'
unset KC_BOOTSTRAP_ADMIN_USERNAME
unset KCRAW_BOOTSTRAP_ADMIN_USERNAME
unset KCRAW_BOOTSTRAP_ADMIN_PASSWORD
export KCRAW_DB_PASSWORD="$(</run/secrets/keycloak_db_password)"
export KCRAW_BOOTSTRAP_ADMIN_CLIENT_SECRET="$(</run/secrets/keycloak_beta_provisioner_secret)"
exec /opt/keycloak/bin/kc.sh bootstrap-admin service --optimized --client-id musicflow-beta-provisioner --client-secret:env KCRAW_BOOTSTRAP_ADMIN_CLIENT_SECRET --no-prompt
'@

try {
    Push-Location $projectRoot

    Invoke-Compose config --quiet
    Invoke-Compose stop keycloak-gateway keycloak
    Invoke-Compose run `
        --rm `
        --no-deps `
        --volume "${publicationSecretFile}:/run/secrets/keycloak_beta_provisioner_secret:ro" `
        --entrypoint /bin/bash `
        keycloak `
        -ceu `
        $bootstrapCommand
    $temporaryClientCreated = $true

    Invoke-Compose up --detach --wait keycloak-gateway
    $gatewayStarted = $true

    $temporaryToken = Get-ProvisionerToken -ClientSecret $publicationSecret
    $headers = @{ Authorization = "Bearer $temporaryToken" }
    $realm = Invoke-RestMethod `
        -Headers $headers `
        -Uri "$adminBaseUrl/admin/realms/musicflow" `
        -TimeoutSec 10
    foreach ($setting in @{
            loginTheme                  = "musicflow"
            internationalizationEnabled = $true
            supportedLocales            = @("es", "en")
            defaultLocale               = "es"
        }.GetEnumerator()) {
        $realm | Add-Member `
            -Force `
            -NotePropertyName $setting.Key `
            -NotePropertyValue $setting.Value
    }
    Invoke-RestMethod `
        -Method Put `
        -Headers $headers `
        -Uri "$adminBaseUrl/admin/realms/musicflow" `
        -ContentType "application/json" `
        -Body ($realm | ConvertTo-Json -Depth 100 -Compress) `
        -TimeoutSec 10 | Out-Null
    $user = Get-ExactBetaUser -Headers $headers

    if ($null -eq $user) {
        $userBody = @{
            username        = $Username
            enabled         = $true
            firstName       = "MusicFlow"
            lastName        = "Beta"
            emailVerified   = $false
            requiredActions = @()
        } | ConvertTo-Json -Depth 4
        $createResponse = Invoke-WebRequest `
            -Method Post `
            -Headers $headers `
            -Uri "$adminBaseUrl/admin/realms/musicflow/users" `
            -ContentType "application/json" `
            -Body $userBody `
            -TimeoutSec 10 `
            -UseBasicParsing
        $location = [string]$createResponse.Headers.Location
        if ([string]::IsNullOrWhiteSpace($location)) {
            throw "Keycloak no devolvio la ubicacion del usuario beta creado."
        }
        $userId = ($location.TrimEnd('/') -split '/')[-1]
        $userCreated = $true
    }
    else {
        $userId = $user.id
        $user.enabled = $true
        $user.firstName = "MusicFlow"
        $user.lastName = "Beta"
        Invoke-RestMethod `
            -Method Put `
            -Headers $headers `
            -Uri "$adminBaseUrl/admin/realms/musicflow/users/$userId" `
            -ContentType "application/json" `
            -Body ($user | ConvertTo-Json -Depth 20 -Compress) `
            -TimeoutSec 10 | Out-Null
    }

    if ($userCreated) {
        $credentialBody = @{
            type      = "password"
            value     = $userPassword
            temporary = $false
        } | ConvertTo-Json -Compress
        Invoke-RestMethod `
            -Method Put `
            -Headers $headers `
            -Uri "$adminBaseUrl/admin/realms/musicflow/users/$userId/reset-password" `
            -ContentType "application/json" `
            -Body $credentialBody `
            -TimeoutSec 10 | Out-Null
    }

    $configuredUser = Get-ExactBetaUser -Headers $headers
    if ($null -eq $configuredUser -or -not $configuredUser.enabled -or $configuredUser.id -ne $userId) {
        throw "El usuario beta no supero la comprobacion posterior al aprovisionamiento."
    }
    $configuredRealm = Invoke-RestMethod `
        -Headers $headers `
        -Uri "$adminBaseUrl/admin/realms/musicflow" `
        -TimeoutSec 10
    if (
        $configuredRealm.loginTheme -ne "musicflow" -or
        -not $configuredRealm.internationalizationEnabled -or
        $configuredRealm.defaultLocale -ne "es"
    ) {
        throw "El tema o idioma de acceso no supero la comprobacion posterior."
    }

    Remove-TemporaryClient -Headers $headers
    $temporaryClientCreated = $false

    try {
        Get-ProvisionerToken -ClientSecret $publicationSecret | Out-Null
        throw "El aprovisionador administrativo temporal todavia puede autenticarse."
    }
    catch {
        $statusCode = if ($_.Exception.Response) {
            [int]$_.Exception.Response.StatusCode
        }
        else {
            0
        }
        if ($statusCode -ne 400 -and $statusCode -ne 401) {
            throw
        }
    }

    Write-Host "Usuario beta controlado aprovisionado y cliente temporal retirado." -ForegroundColor Green
    Write-Host "Usuario: $Username" -ForegroundColor Green
    Write-Host "Contrasena local: .secrets/keycloak-beta-user-password" -ForegroundColor Green
}
finally {
    try {
        if ($dockerExecutable -and -not $gatewayStarted) {
            Invoke-Compose up --detach --wait keycloak-gateway
            $gatewayStarted = $true
        }
        if ($dockerExecutable -and $gatewayStarted -and $temporaryClientCreated) {
            $cleanupToken = Get-ProvisionerToken -ClientSecret $publicationSecret
            $cleanupHeaders = @{ Authorization = "Bearer $cleanupToken" }
            Remove-TemporaryClient -Headers $cleanupHeaders
        }
    }
    finally {
        $publicationSecret = $null
        $userPassword = $null
        $temporaryToken = $null
        $headers = $null
        $credentialBody = $null
        $cleanupToken = $null
        $cleanupHeaders = $null
        $env:KEYCLOAK_PROXY_SUBNET = $previousProxySubnet
        Pop-Location -ErrorAction SilentlyContinue
    }
}
