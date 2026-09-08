#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Download Elastic Agent from the SIEM host mirror (if needed) and enroll it.

.EXAMPLE
  .\install-agent.ps1 `
    -FleetUrl "https://192.168.1.108:8220" `
    -Token    "<enrollment-token>"

  Optional: -CaCertPath, -Version, -ArtifactsPort (default 9080).
  Get the token from Kibana → Fleet → Add agent → Endpoint Policy.
#>
param(
    [Parameter(Mandatory)]
    [string]$FleetUrl,

    [Parameter(Mandatory)]
    [string]$Token,

    [string]$CaCertPath = "",

    [string]$Version = "9.5.3",

    [int]$ArtifactsPort = 9080
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$fleetHost = ([Uri]$FleetUrl).Host
if (-not $fleetHost) {
    Write-Error "Cannot parse host from FleetUrl: $FleetUrl"
    exit 1
}
$mirror = "http://${fleetHost}:${ArtifactsPort}"

if (-not $CaCertPath -or -not (Test-Path $CaCertPath)) {
    $CaCertPath = Join-Path $env:TEMP "elk-ca.crt"
    Write-Host "==> Downloading CA from $mirror/ca.crt" -ForegroundColor Cyan
    Invoke-WebRequest -Uri "$mirror/ca.crt" -OutFile $CaCertPath -UseBasicParsing
}

$agentExe = $null
if (Test-Path '.\elastic-agent.exe') {
    $agentExe = (Resolve-Path '.\elastic-agent.exe').Path
} else {
    $zipName = "elastic-agent-$Version-windows-x86_64.zip"
    $zipUrl = "$mirror/downloads/beats/elastic-agent/$zipName"
    $zipPath = Join-Path $env:TEMP $zipName
    $extractDir = Join-Path $env:TEMP "elastic-agent-$Version"
    Write-Host "==> Downloading Elastic Agent from $zipUrl" -ForegroundColor Cyan
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath -UseBasicParsing
    if (Test-Path $extractDir) { Remove-Item -Recurse -Force $extractDir }
    Expand-Archive -Path $zipPath -DestinationPath $extractDir
    $found = Get-ChildItem -Path $extractDir -Filter elastic-agent.exe -Recurse | Select-Object -First 1
    if (-not $found) {
        Write-Error "elastic-agent.exe not found after extracting $zipName"
        exit 1
    }
    $agentExe = $found.FullName
}

Write-Host "==> Installing CA certificate into Windows trust store..." -ForegroundColor Cyan
Import-Certificate -FilePath $CaCertPath -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
Write-Host "    Done (Cert:\LocalMachine\Root)" -ForegroundColor Green

Write-Host "==> Installing Elastic Agent..." -ForegroundColor Cyan
& $agentExe install `
    --url=$FleetUrl `
    --enrollment-token=$Token `
    --certificate-authorities=$CaCertPath

Write-Host "==> Done. Check agent status: elastic-agent status" -ForegroundColor Green
