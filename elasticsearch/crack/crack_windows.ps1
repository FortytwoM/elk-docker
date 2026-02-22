Param(
    [Parameter(Mandatory = $true)]
    [string]$Version
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

docker build --no-cache -f "$ScriptDir\Dockerfile" --build-arg VERSION=$Version -t "elastic-xpack-crack:$Version" $ScriptDir

New-Item -ItemType Directory -Path "$ScriptDir\output" -Force | Out-Null

docker run --rm `
  -v "$ScriptDir\output:/crack/output" `
  "elastic-xpack-crack:$Version"

Write-Host ""
Write-Host "Cracked jar: $ScriptDir\output\x-pack-core-$Version.crack.jar"
