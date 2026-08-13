[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)][int]$AdminPort = 8081,
    [string]$ProjectName = "musicflow",
    [ValidatePattern('^\d{1,3}(?:\.\d{1,3}){3}/\d{1,2}$')][string]$ProxySubnet
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$composeFile = Join-Path $projectRoot "compose.yaml"
$envFile = Join-Path $projectRoot ".env"
$publicationSecretFile = Join-Path $projectRoot ".secrets\keycloak-publication-admin-client-secret"
$adminBaseUrl = "http://127.0.0.1:$AdminPort"
$temporaryClientId = "musicflow-publication-admin"
$dockerExecutable = $null
$temporaryToken = $null
$temporaryClientUuid = $null
$temporaryClientCreated = $false
$gatewayStarted = $false
$previousProxySubnet = $env:KEYCLOAK_PROXY_SUBNET

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
        throw "No existe el secreto temporal de publicacion. Ejecuta initialize-identity-secrets.ps1."
    }

    $value = (Get-Content -LiteralPath $Path -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "El secreto temporal de publicacion esta vacio."
    }

    return $value
}

function Get-PublicationAdminToken {
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

function Remove-TemporaryClient {
    param([Parameter(Mandatory = $true)][hashtable]$Headers)

    $clientsResponse = Invoke-RestMethod `
        -Headers $Headers `
        -Uri "$script:adminBaseUrl/admin/realms/master/clients?clientId=$script:temporaryClientId" `
        -TimeoutSec 10
    $clients = @($clientsResponse | ForEach-Object { $_ })

    if ($clients.Count -gt 1) {
        throw "Existe mas de un cliente administrativo temporal de publicacion."
    }

    if ($clients.Count -eq 1) {
        $script:temporaryClientUuid = $clients[0].id
        Invoke-RestMethod `
            -Method Delete `
            -Headers $Headers `
            -Uri "$script:adminBaseUrl/admin/realms/master/clients/$($script:temporaryClientUuid)" `
            -TimeoutSec 10 | Out-Null
    }
}

if ($ProjectName -notmatch '^musicflow(?:-[a-z0-9-]+)?$') {
    throw "ProjectName debe pertenecer a un proyecto MusicFlow controlado."
}
if (-not (Test-Path -LiteralPath $envFile)) {
    throw "No existe .env. Conserva la configuracion local antes de migrar identidad."
}

$publicationSecret = Read-Secret -Path $publicationSecretFile
$dockerExecutable = Resolve-DockerExecutable
if ($PSBoundParameters.ContainsKey("ProxySubnet")) {
    $env:KEYCLOAK_PROXY_SUBNET = $ProxySubnet
}
elseif ([string]::IsNullOrWhiteSpace($env:KEYCLOAK_PROXY_SUBNET)) {
    $envFileContent = Get-Content -LiteralPath $envFile
    $proxySubnetLine = @(
        $envFileContent | Where-Object { $_ -match '^\s*KEYCLOAK_PROXY_SUBNET\s*=' }
    ) | Select-Object -Last 1
    if ($proxySubnetLine) {
        $env:KEYCLOAK_PROXY_SUBNET = ($proxySubnetLine -split '=', 2)[1].Trim()
    }
}
$bootstrapCommand = @'
unset KC_BOOTSTRAP_ADMIN_USERNAME
unset KCRAW_BOOTSTRAP_ADMIN_USERNAME
unset KCRAW_BOOTSTRAP_ADMIN_PASSWORD
export KCRAW_DB_PASSWORD="$(</run/secrets/keycloak_db_password)"
export KCRAW_BOOTSTRAP_ADMIN_CLIENT_SECRET="$(</run/secrets/keycloak_publication_admin_client_secret)"
exec /opt/keycloak/bin/kc.sh bootstrap-admin service --optimized --client-id musicflow-publication-admin --client-secret:env KCRAW_BOOTSTRAP_ADMIN_CLIENT_SECRET --no-prompt
'@

try {
    Push-Location $projectRoot

    Invoke-Compose config --quiet
    Invoke-Compose stop keycloak-gateway keycloak

    Invoke-Compose run `
        --rm `
        --no-deps `
        --volume "${publicationSecretFile}:/run/secrets/keycloak_publication_admin_client_secret:ro" `
        --entrypoint /bin/bash `
        keycloak `
        -ceu `
        $bootstrapCommand
    $temporaryClientCreated = $true

    Invoke-Compose up --detach --wait keycloak-gateway
    $gatewayStarted = $true

    $temporaryToken = Get-PublicationAdminToken -ClientSecret $publicationSecret
    $headers = @{ Authorization = "Bearer $temporaryToken" }

    $masterRealm = Invoke-RestMethod `
        -Headers $headers `
        -Uri "$adminBaseUrl/admin/realms/master" `
        -TimeoutSec 10
    if ($null -eq $masterRealm.attributes) {
        $masterRealm | Add-Member -NotePropertyName attributes -NotePropertyValue ([pscustomobject]@{})
    }
    $masterRealm.attributes | Add-Member `
        -Force `
        -NotePropertyName frontendUrl `
        -NotePropertyValue $adminBaseUrl

    Invoke-RestMethod `
        -Method Put `
        -Headers $headers `
        -Uri "$adminBaseUrl/admin/realms/master" `
        -ContentType "application/json" `
        -Body ($masterRealm | ConvertTo-Json -Depth 100 -Compress) `
        -TimeoutSec 10 | Out-Null

    $consoleResponse = Invoke-WebRequest `
        -UseBasicParsing `
        -Uri "$adminBaseUrl/admin/master/console/" `
        -TimeoutSec 10
    $environmentMatch = [regex]::Match(
        $consoleResponse.Content,
        '<script id="environment" type="application/json">\s*(?<json>.*?)\s*</script>',
        'Singleline'
    )
    if (-not $environmentMatch.Success) {
        throw "No se pudo inspeccionar la configuracion de la consola administrativa."
    }
    $consoleEnvironment = $environmentMatch.Groups["json"].Value | ConvertFrom-Json
    if ($consoleEnvironment.authServerUrl -ne $adminBaseUrl) {
        throw "El login del realm master no quedo ligado a la puerta local."
    }

    Remove-TemporaryClient -Headers $headers
    $temporaryClientCreated = $false

    try {
        Get-PublicationAdminToken -ClientSecret $publicationSecret | Out-Null
        throw "El cliente administrativo temporal todavia puede autenticarse."
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

    Write-Host "Realm master aislado en la puerta administrativa local." -ForegroundColor Green
}
finally {
    try {
        if ($dockerExecutable -and -not $gatewayStarted) {
            Invoke-Compose up --detach --wait keycloak-gateway
            $gatewayStarted = $true
        }

        if ($dockerExecutable -and $gatewayStarted -and $temporaryClientCreated) {
            $cleanupToken = Get-PublicationAdminToken -ClientSecret $publicationSecret
            $cleanupHeaders = @{ Authorization = "Bearer $cleanupToken" }
            Remove-TemporaryClient -Headers $cleanupHeaders
            $temporaryClientCreated = $false
        }
    }
    finally {
        $publicationSecret = $null
        $temporaryToken = $null
        $headers = $null
        $masterRealm = $null
        $consoleEnvironment = $null
        $cleanupToken = $null
        $cleanupHeaders = $null
        $env:KEYCLOAK_PROXY_SUBNET = $previousProxySubnet
        Pop-Location -ErrorAction SilentlyContinue
    }
}
