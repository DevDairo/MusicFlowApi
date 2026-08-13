[CmdletBinding()]
param(
    [switch]$KeepRunning,
    [ValidateRange(1024, 65535)][int]$ApiPort = 8000
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$composeFile = Join-Path $projectRoot "compose.yaml"
$envFile = Join-Path $projectRoot ".env.example"
$projectName = "musicflow-verify"
$previousApiPort = $env:MUSICFLOW_API_PORT
$env:MUSICFLOW_API_PORT = [string]$ApiPort

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

    throw "No se encontro docker.exe. Confirma que Docker Desktop este instalado y accesible para este usuario."
}

function Invoke-Compose {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

    & $script:dockerExecutable compose `
        --project-name $script:projectName `
        --env-file $script:envFile `
        --file $script:composeFile `
        @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "docker compose termino con codigo $LASTEXITCODE."
    }
}

$dockerExecutable = Resolve-DockerExecutable

try {
    Push-Location $projectRoot

    Invoke-Compose config --quiet
    $composeConfiguration = (Invoke-Compose config --format json) | ConvertFrom-Json
    if ($composeConfiguration.services.postgres.PSObject.Properties.Name -contains "ports") {
        throw "PostgreSQL no debe publicar puertos."
    }
    if ($composeConfiguration.services.worker.PSObject.Properties.Name -contains "ports") {
        throw "El worker no debe publicar puertos."
    }

    Invoke-Compose build api worker tests
    $apiUser = (Invoke-Compose run --rm --no-deps api id -u | Out-String).Trim()
    $workerUser = (Invoke-Compose run --rm --no-deps worker id -u | Out-String).Trim()
    if ($apiUser -ne "10001" -or $workerUser -ne "10001") {
        throw "API y worker deben ejecutarse como el usuario no root 10001."
    }
    Invoke-Compose run --rm --no-deps tests python -m pip check
    Invoke-Compose run --rm --no-deps tests ruff check --no-cache src tests migrations
    Invoke-Compose run --rm --no-deps tests ruff format --check --no-cache src tests migrations

    Invoke-Compose up --detach --wait api worker
    Invoke-Compose -Arguments @(
        "run",
        "--rm",
        "tests",
        "pytest",
        "-q",
        "-p",
        "no:cacheprovider"
    )

    $live = Invoke-RestMethod -Uri "http://127.0.0.1:$ApiPort/health/live" -TimeoutSec 5
    $ready = Invoke-RestMethod -Uri "http://127.0.0.1:$ApiPort/health/ready" -TimeoutSec 5

    if ($live.status -ne "alive") {
        throw "El health check live no devolvio el estado esperado."
    }
    if ($ready.status -ne "ready") {
        throw "El health check ready no devolvio el estado esperado."
    }

    Invoke-Compose ps
    Write-Host "Verificacion completada correctamente." -ForegroundColor Green
}
finally {
    try {
        if (-not $KeepRunning -and $dockerExecutable) {
            Invoke-Compose down --volumes --remove-orphans
        }
    }
    finally {
        $env:MUSICFLOW_API_PORT = $previousApiPort
        Pop-Location -ErrorAction SilentlyContinue
    }
}
