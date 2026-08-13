[CmdletBinding()]
param(
    [switch]$AcceptMicrosoftSdkLicense,
    [switch]$SkipInstaller
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$desktopRoot = Join-Path $projectRoot "desktop"
$dockerfile = Join-Path $desktopRoot "Dockerfile"
$pnpmLock = Join-Path $desktopRoot "pnpm-lock.yaml"
$cargoLock = Join-Path $desktopRoot "src-tauri\Cargo.lock"
$qualityImage = "musicflow-desktop-quality:local"

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

    throw "No se encontro docker.exe. Confirma que Docker Desktop este activo para este usuario."
}

function Invoke-Docker {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)

    & $script:dockerExecutable @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Docker termino con codigo $LASTEXITCODE."
    }
}

function Initialize-Lockfiles {
    if ((Test-Path -LiteralPath $script:pnpmLock) -and (Test-Path -LiteralPath $script:cargoLock)) {
        return
    }

    $temporaryRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    $lockDirectory = Join-Path $temporaryRoot ("musicflow-locks-" + [guid]::NewGuid().ToString("N"))

    try {
        Write-Host "Generando lockfiles reproducibles dentro de Docker..." -ForegroundColor Cyan
        Invoke-Docker build `
            --file $script:dockerfile `
            --target lockfiles `
            --output "type=local,dest=$lockDirectory" `
            $script:desktopRoot

        if (-not (Test-Path -LiteralPath $script:pnpmLock)) {
            Copy-Item -LiteralPath (Join-Path $lockDirectory "pnpm-lock.yaml") -Destination $script:pnpmLock
        }
        if (-not (Test-Path -LiteralPath $script:cargoLock)) {
            Copy-Item -LiteralPath (Join-Path $lockDirectory "src-tauri\Cargo.lock") -Destination $script:cargoLock
        }
    }
    finally {
        $resolvedLockDirectory = [System.IO.Path]::GetFullPath($lockDirectory)
        $temporaryPrefix = $temporaryRoot.TrimEnd("\") + "\"
        if (
            (Test-Path -LiteralPath $resolvedLockDirectory) -and
            $resolvedLockDirectory.StartsWith($temporaryPrefix, [System.StringComparison]::OrdinalIgnoreCase) -and
            ([System.IO.Path]::GetFileName($resolvedLockDirectory) -like "musicflow-locks-*")
        ) {
            Remove-Item -LiteralPath $resolvedLockDirectory -Recurse -Force
        }
    }
}

$dockerExecutable = Resolve-DockerExecutable

if (-not $SkipInstaller -and -not $AcceptMicrosoftSdkLicense) {
    throw "La compilacion con cargo-xwin requiere aceptar la licencia del SDK de Microsoft. Revisa la documentacion y usa -AcceptMicrosoftSdkLicense para continuar."
}

Push-Location $projectRoot
try {
    Invoke-Docker info --format "Docker Engine {{.ServerVersion}}"
    Initialize-Lockfiles

    Write-Host "Ejecutando formato, lint, pruebas y build web dentro de Docker..." -ForegroundColor Cyan
    Invoke-Docker build `
        --file $dockerfile `
        --target quality `
        --tag $qualityImage `
        $desktopRoot

    if ($SkipInstaller) {
        Write-Host "Calidad del cliente verificada; instalador omitido por parametro." -ForegroundColor Green
        return
    }

    $artifactsRoot = Join-Path $projectRoot "artifacts"
    $artifactDirectory = Join-Path $artifactsRoot ("desktop-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
    New-Item -ItemType Directory -Path $artifactsRoot -Force | Out-Null

    Write-Host "Compilando el instalador NSIS de Windows dentro de Docker..." -ForegroundColor Cyan
    Invoke-Docker build `
        --file $dockerfile `
        --target artifact `
        --build-arg "ACCEPT_MICROSOFT_SDK_LICENSE=yes" `
        --output "type=local,dest=$artifactDirectory" `
        $desktopRoot

    $installers = @(Get-ChildItem -LiteralPath $artifactDirectory -Filter "*-setup.exe" -File)
    if ($installers.Count -ne 1) {
        throw "Se esperaba exactamente un instalador NSIS y se encontraron $($installers.Count)."
    }

    Write-Host "Verificacion completada correctamente." -ForegroundColor Green
    Write-Host "Instalador: $($installers[0].FullName)" -ForegroundColor Green
}
finally {
    Pop-Location -ErrorAction SilentlyContinue
}
