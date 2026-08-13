[CmdletBinding()]
param(
    [ValidatePattern('^https://[A-Za-z0-9.-]+$')]
    [string]$PublicBaseUrl = "https://auth.kontora-pos.store",
    [ValidateRange(1024, 65535)][int]$AdminPort = 8081
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$adminBaseUrl = "http://127.0.0.1:$AdminPort"
$expectedIssuer = "$PublicBaseUrl/realms/musicflow"

function Get-HttpStatusCode {
    param([Parameter(Mandatory = $true)][string]$Uri)

    try {
        $response = Invoke-WebRequest `
            -Uri $Uri `
            -MaximumRedirection 0 `
            -TimeoutSec 15 `
            -UseBasicParsing
        return [int]$response.StatusCode
    }
    catch {
        if ($_.Exception.Response) {
            return [int]$_.Exception.Response.StatusCode
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

$discovery = Invoke-RestMethod `
    -Uri "$expectedIssuer/.well-known/openid-configuration" `
    -TimeoutSec 15
Assert-Equal $discovery.issuer $expectedIssuer "El issuer publico no coincide."
Assert-Equal `
    $discovery.jwks_uri `
    "$expectedIssuer/protocol/openid-connect/certs" `
    "Discovery anuncio un JWKS inesperado."
Assert-True `
    -Condition ([bool]($discovery.code_challenge_methods_supported -contains "S256")) `
    -Message "Discovery publico no anuncia PKCE S256."

$jwks = Invoke-RestMethod -Uri $discovery.jwks_uri -TimeoutSec 15
Assert-True -Condition ($jwks.keys.Count -gt 0) -Message "JWKS publico no contiene claves."

$authorizationUri = "$($discovery.authorization_endpoint)?client_id=musicflow-desktop&response_type=code&scope=openid&redirect_uri=http%3A%2F%2F127.0.0.1&code_challenge=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&code_challenge_method=S256"
$authorizationStatus = Get-HttpStatusCode $authorizationUri
Assert-True `
    -Condition ($authorizationStatus -eq 200 -or $authorizationStatus -eq 302) `
    -Message "El inicio de login publico no responde con 200/302. Estado: $authorizationStatus."

foreach ($deniedPath in @(
        "/",
        "/admin/",
        "/admin/master/console/",
        "/realms/master/",
        "/realms/master/.well-known/openid-configuration",
        "/health",
        "/health/ready",
        "/metrics",
        "/gateway-health"
    )) {
    Assert-Equal `
        (Get-HttpStatusCode "$PublicBaseUrl$deniedPath") `
        404 `
        "La frontera publica expuso una ruta denegada: $deniedPath."
}

$consoleResponse = Invoke-WebRequest `
    -UseBasicParsing `
    -Uri "$adminBaseUrl/admin/master/console/" `
    -TimeoutSec 10
$environmentMatch = [regex]::Match(
    $consoleResponse.Content,
    '<script id="environment" type="application/json">\s*(?<json>.*?)\s*</script>',
    'Singleline'
)
Assert-True `
    -Condition $environmentMatch.Success `
    -Message "No se pudo inspeccionar la consola administrativa local."
$consoleEnvironment = $environmentMatch.Groups["json"].Value | ConvertFrom-Json
Assert-Equal `
    $consoleEnvironment.authServerUrl `
    $adminBaseUrl `
    "El realm master intento autenticar fuera de la puerta local."
Assert-Equal `
    $consoleEnvironment.adminBaseUrl `
    $adminBaseUrl `
    "La API administrativa no quedo ligada a loopback."

Write-Host "Publicacion OIDC verificada: rutas publicas minimas y administracion local." -ForegroundColor Green
