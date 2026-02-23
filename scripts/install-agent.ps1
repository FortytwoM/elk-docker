#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Enroll an Elastic Agent on Windows.
  Installs the stack CA into the system trust store (required for Elastic Defend)
  and enrolls the agent into Fleet.

.EXAMPLE
  .\install-agent.ps1 `
    -FleetUrl   "https://192.168.1.100:8220" `
    -Token      "<enrollment-token>" `
    -CaCertPath "C:\path\to\ca.crt"

.NOTES
  Run from the extracted elastic-agent directory (where elastic-agent.exe lives).
  Get the enrollment token from Kibana -> Fleet -> Add agent -> select policy.
#>
param(
    [Parameter(Mandatory)]
    [string]$FleetUrl,

    [Parameter(Mandatory)]
    [string]$Token,

    [Parameter(Mandatory)]
    [string]$CaCertPath
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $CaCertPath)) {
    Write-Error "CA certificate not found: $CaCertPath"
    exit 1
}

if (-not (Test-Path '.\elastic-agent.exe')) {
    Write-Error "elastic-agent.exe not found in current directory. cd to the extracted agent folder first."
    exit 1
}

Write-Host "==> Installing CA certificate into Windows trust store..." -ForegroundColor Cyan
Import-Certificate -FilePath $CaCertPath -CertStoreLocation Cert:\LocalMachine\Root | Out-Null
Write-Host "    Done (Cert:\LocalMachine\Root)" -ForegroundColor Green

Write-Host "==> Installing Elastic Agent..." -ForegroundColor Cyan
& .\elastic-agent.exe install `
    --url=$FleetUrl `
    --enrollment-token=$Token `
    --certificate-authorities=$CaCertPath

Write-Host "==> Done. Check agent status: elastic-agent status" -ForegroundColor Green
