[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)][int]$AdminPort = 8081,
    [string]$BootstrapUsername = "temp-admin",
    [string]$AdminUsername = "musicflow-admin"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$secretDirectory = Join-Path $projectRoot ".secrets"
$bootstrapPasswordFile = Join-Path $secretDirectory "keycloak-bootstrap-admin-password"
$adminPasswordFile = Join-Path $secretDirectory "keycloak-admin-password"
$verifierSecretFile = Join-Path $secretDirectory "keycloak-verifier-client-secret"
$bootstrapUsername = $BootstrapUsername.Trim()
$adminUsername = $AdminUsername.Trim()
$adminBaseUrl = "http://127.0.0.1:$AdminPort"
$verifierClientId = "musicflow-identity-verifier"

if ([string]::IsNullOrWhiteSpace($bootstrapUsername)) {
    throw "BootstrapUsername no puede estar vacio."
}
if ([string]::IsNullOrWhiteSpace($adminUsername)) {
    throw "AdminUsername no puede estar vacio."
}
if ($bootstrapUsername -eq $adminUsername) {
    throw "La cuenta bootstrap y el administrador permanente deben ser diferentes."
}

function Assert-LocalAdminUrl {
    $uri = [Uri]$script:adminBaseUrl
    if ($uri.Scheme -ne "http" -or $uri.Host -ne "127.0.0.1") {
        throw "El aprovisionamiento administrativo solo puede usar 127.0.0.1 por HTTP."
    }
}

function Read-Secret {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "No existe el secreto requerido: $Path"
    }

    $value = (Get-Content -LiteralPath $Path -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "El secreto requerido esta vacio: $Path"
    }

    return $value
}

function Get-AdminToken {
    param(
        [Parameter(Mandatory = $true)][string]$Username,
        [Parameter(Mandatory = $true)][string]$Password
    )

    $response = Invoke-RestMethod `
        -Method Post `
        -Uri "$script:adminBaseUrl/realms/master/protocol/openid-connect/token" `
        -ContentType "application/x-www-form-urlencoded" `
        -Body @{
            client_id  = "admin-cli"
            grant_type = "password"
            username   = $Username
            password   = $Password
        } `
        -TimeoutSec 10

    if ([string]::IsNullOrWhiteSpace($response.access_token)) {
        throw "Keycloak no entrego un token administrativo."
    }

    return $response.access_token
}

function Get-VerifierToken {
    param([Parameter(Mandatory = $true)][string]$ClientSecret)

    $response = Invoke-RestMethod `
        -Method Post `
        -Uri "$script:adminBaseUrl/realms/master/protocol/openid-connect/token" `
        -ContentType "application/x-www-form-urlencoded" `
        -Body @{
            client_id     = $script:verifierClientId
            client_secret = $ClientSecret
            grant_type    = "client_credentials"
        } `
        -TimeoutSec 10

    if ([string]::IsNullOrWhiteSpace($response.access_token)) {
        throw "Keycloak no entrego un token al verificador local."
    }

    return $response.access_token
}

function Test-VerifierReady {
    param([Parameter(Mandatory = $true)][string]$ClientSecret)

    try {
        $token = Get-VerifierToken -ClientSecret $ClientSecret
        $headers = @{ Authorization = "Bearer $token" }

        $clients = Invoke-RestMethod `
            -Headers $headers `
            -Uri "$script:adminBaseUrl/admin/realms/musicflow/clients?clientId=musicflow-desktop" `
            -TimeoutSec 10
        return @($clients | ForEach-Object { $_ }).Count -eq 1
    }
    catch {
        return $false
    }
    finally {
        $token = $null
        $headers = $null
    }
}

function Get-ExactUser {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Headers,
        [Parameter(Mandatory = $true)][string]$Username
    )

    $encodedUsername = [Uri]::EscapeDataString($Username)
    $response = Invoke-RestMethod `
            -Headers $Headers `
            -Uri "$script:adminBaseUrl/admin/realms/master/users?username=$encodedUsername&exact=true" `
            -TimeoutSec 10
    $users = @($response | ForEach-Object { $_ })

    if ($users.Count -gt 1) {
        throw "Existe mas de un usuario administrativo con el nombre exacto $Username."
    }

    if ($users.Count -eq 1) {
        return $users[0]
    }

    return $null
}

function Test-PermanentAdmin {
    param([Parameter(Mandatory = $true)][string]$Password)

    try {
        $token = Get-AdminToken -Username $script:adminUsername -Password $Password
        $headers = @{ Authorization = "Bearer $token" }
        $serverInfo = Invoke-RestMethod `
            -Headers $headers `
            -Uri "$script:adminBaseUrl/admin/serverinfo" `
            -TimeoutSec 10
        if ($null -eq $serverInfo.systemInfo) {
            return $false
        }

        $realm = Invoke-RestMethod `
            -Headers $headers `
            -Uri "$script:adminBaseUrl/admin/realms/musicflow" `
            -TimeoutSec 10
        return $null -ne $realm.PSObject.Properties["passwordPolicy"]
    }
    catch {
        return $false
    }
    finally {
        $token = $null
        $headers = $null
    }
}

Assert-LocalAdminUrl

$adminPassword = Read-Secret -Path $adminPasswordFile
$verifierClientSecret = Read-Secret -Path $verifierSecretFile
$bootstrapPassword = $null
$bootstrapToken = $null
$permanentToken = $null
$headers = $null

try {
    if (Test-VerifierReady -ClientSecret $verifierClientSecret) {
        Write-Host "Identidad ya aprovisionada; no se requieren cambios administrativos." -ForegroundColor Green
        return
    }

    if (-not (Test-PermanentAdmin -Password $adminPassword)) {
        $bootstrapPassword = Read-Secret -Path $bootstrapPasswordFile
        $bootstrapToken = Get-AdminToken `
            -Username $bootstrapUsername `
            -Password $bootstrapPassword
        $headers = @{ Authorization = "Bearer $bootstrapToken" }

        $existingAdmin = Get-ExactUser -Headers $headers -Username $adminUsername
        if ($null -eq $existingAdmin) {
            $userBody = @{
                username    = $adminUsername
                enabled     = $true
                credentials = @(
                    @{
                        type      = "password"
                        value     = $adminPassword
                        temporary = $false
                    }
                )
            } | ConvertTo-Json -Depth 5

            $createResponse = Invoke-WebRequest `
                -Method Post `
                -Headers $headers `
                -Uri "$adminBaseUrl/admin/realms/master/users" `
                -ContentType "application/json" `
                -Body $userBody `
                -TimeoutSec 10 `
                -UseBasicParsing

            $location = [string]$createResponse.Headers.Location
            if ([string]::IsNullOrWhiteSpace($location)) {
                throw "Keycloak no devolvio la ubicacion del administrador creado."
            }
            $adminUserId = ($location.TrimEnd("/") -split "/")[-1]
        }
        else {
            $adminUserId = $existingAdmin.id
        }

        $realmAdminRole = Invoke-RestMethod `
            -Headers $headers `
            -Uri "$adminBaseUrl/admin/realms/master/roles/admin" `
            -TimeoutSec 10
        $roleBody = ConvertTo-Json -InputObject @($realmAdminRole) -Depth 5

        Invoke-RestMethod `
            -Method Post `
            -Headers $headers `
            -Uri "$adminBaseUrl/admin/realms/master/users/$adminUserId/role-mappings/realm" `
            -ContentType "application/json" `
            -Body $roleBody `
            -TimeoutSec 10 | Out-Null

        if (-not (Test-PermanentAdmin -Password $adminPassword)) {
            throw "El administrador permanente fue creado, pero no supero la comprobacion de acceso."
        }
    }

    $permanentToken = Get-AdminToken -Username $adminUsername -Password $adminPassword
    $headers = @{ Authorization = "Bearer $permanentToken" }

    $verifierClientResponse = Invoke-RestMethod `
        -Headers $headers `
        -Uri "$adminBaseUrl/admin/realms/master/clients?clientId=$verifierClientId" `
        -TimeoutSec 10
    $verifierClients = @($verifierClientResponse | ForEach-Object { $_ })

    $verifierClientBody = @{
        clientId                  = $verifierClientId
        name                      = "MusicFlow identity verifier"
        description               = "Local read-only verifier for the musicflow realm."
        enabled                   = $true
        protocol                  = "openid-connect"
        publicClient              = $false
        bearerOnly                = $false
        standardFlowEnabled       = $false
        implicitFlowEnabled       = $false
        directAccessGrantsEnabled = $false
        serviceAccountsEnabled    = $true
        clientAuthenticatorType   = "client-secret"
        secret                    = $verifierClientSecret
        fullScopeAllowed          = $false
    } | ConvertTo-Json -Depth 4

    if ($verifierClients.Count -eq 0) {
        Invoke-RestMethod `
            -Method Post `
            -Headers $headers `
            -Uri "$adminBaseUrl/admin/realms/master/clients" `
            -ContentType "application/json" `
            -Body $verifierClientBody `
            -TimeoutSec 10 | Out-Null

        $verifierClientResponse = Invoke-RestMethod `
            -Headers $headers `
            -Uri "$adminBaseUrl/admin/realms/master/clients?clientId=$verifierClientId" `
            -TimeoutSec 10
        $verifierClients = @($verifierClientResponse | ForEach-Object { $_ })
    }
    elseif ($verifierClients.Count -eq 1) {
        Invoke-RestMethod `
            -Method Put `
            -Headers $headers `
            -Uri "$adminBaseUrl/admin/realms/master/clients/$($verifierClients[0].id)" `
            -ContentType "application/json" `
            -Body $verifierClientBody `
            -TimeoutSec 10 | Out-Null
    }

    if ($verifierClients.Count -ne 1) {
        throw "Debe existir exactamente un cliente local de verificacion."
    }

    $verifierClientUuid = $verifierClients[0].id
    $serviceAccountUser = Invoke-RestMethod `
        -Headers $headers `
        -Uri "$adminBaseUrl/admin/realms/master/clients/$verifierClientUuid/service-account-user" `
        -TimeoutSec 10

    $realmClientResponse = Invoke-RestMethod `
        -Headers $headers `
        -Uri "$adminBaseUrl/admin/realms/master/clients?clientId=musicflow-realm" `
        -TimeoutSec 10
    $realmClients = @($realmClientResponse | ForEach-Object { $_ })
    if ($realmClients.Count -ne 1) {
        throw "No se encontro exactamente un cliente administrativo musicflow-realm."
    }

    $realmClientUuid = $realmClients[0].id
    $readOnlyRoles = @()
    foreach ($roleName in @("query-clients", "view-clients", "view-realm")) {
        $readOnlyRoles += Invoke-RestMethod `
            -Headers $headers `
            -Uri "$adminBaseUrl/admin/realms/master/clients/$realmClientUuid/roles/$roleName" `
            -TimeoutSec 10
    }

    Invoke-RestMethod `
        -Method Post `
        -Headers $headers `
        -Uri "$adminBaseUrl/admin/realms/master/users/$($serviceAccountUser.id)/role-mappings/clients/$realmClientUuid" `
        -ContentType "application/json" `
        -Body (ConvertTo-Json -InputObject @($readOnlyRoles) -Depth 5) `
        -TimeoutSec 10 | Out-Null

    Invoke-RestMethod `
        -Method Post `
        -Headers $headers `
        -Uri "$adminBaseUrl/admin/realms/master/clients/$verifierClientUuid/scope-mappings/clients/$realmClientUuid" `
        -ContentType "application/json" `
        -Body (ConvertTo-Json -InputObject @($readOnlyRoles) -Depth 5) `
        -TimeoutSec 10 | Out-Null

    $temporaryAdmin = Get-ExactUser -Headers $headers -Username $bootstrapUsername

    if ($null -ne $temporaryAdmin -and $temporaryAdmin.username -ne $adminUsername) {
        Invoke-RestMethod `
            -Method Delete `
            -Headers $headers `
            -Uri "$adminBaseUrl/admin/realms/master/users/$($temporaryAdmin.id)" `
            -TimeoutSec 10 | Out-Null
    }

    if (-not (Test-VerifierReady -ClientSecret $verifierClientSecret)) {
        throw "El verificador local no supero la comprobacion de lectura."
    }

    Write-Host "Administrador permanente, verificador local y retiro de bootstrap preparados." -ForegroundColor Green
}
finally {
    $adminPassword = $null
    $verifierClientSecret = $null
    $bootstrapPassword = $null
    $bootstrapToken = $null
    $permanentToken = $null
    $headers = $null
}
