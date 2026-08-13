[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$secretDirectory = Join-Path $projectRoot ".secrets"
$utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)

function New-Base64UrlSecret {
    param([int]$ByteCount = 48)

    $bytes = New-Object byte[] $ByteCount
    $generator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $generator.GetBytes($bytes)
    }
    finally {
        $generator.Dispose()
    }

    return [Convert]::ToBase64String($bytes).TrimEnd("=").Replace("+", "-").Replace("/", "_")
}

if (-not (Test-Path -LiteralPath $secretDirectory)) {
    New-Item -ItemType Directory -Path $secretDirectory | Out-Null
}

$secretFiles = @(
    "keycloak-db-password",
    "keycloak-bootstrap-admin-password",
    "keycloak-admin-password",
    "keycloak-verifier-client-secret",
    "keycloak-publication-admin-client-secret"
)

foreach ($secretFile in $secretFiles) {
    $secretPath = Join-Path $secretDirectory $secretFile

    if (Test-Path -LiteralPath $secretPath) {
        if ((Get-Item -LiteralPath $secretPath).Length -eq 0) {
            throw "El secreto existente esta vacio: $secretPath"
        }

        Write-Host "Conservado: .secrets/$secretFile" -ForegroundColor Yellow
        continue
    }

    [System.IO.File]::WriteAllText($secretPath, (New-Base64UrlSecret), $utf8WithoutBom)
    Write-Host "Creado: .secrets/$secretFile" -ForegroundColor Green
}

& git -C $projectRoot check-ignore --quiet -- ".secrets/keycloak-db-password"
if ($LASTEXITCODE -ne 0) {
    throw "La ruta de secretos no esta protegida por .gitignore."
}

Write-Host "Secretos de identidad preparados sin mostrar su contenido." -ForegroundColor Green
