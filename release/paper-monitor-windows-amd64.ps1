param(
  [Parameter(Mandatory = $true, Position = 0)]
  [ValidateSet("setup", "run")]
  [string]$Mode
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $RootDir

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
  throw "Docker Desktop is required."
}
docker info | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw "Docker is installed but its daemon is not running."
}
docker compose version | Out-Null
if ($LASTEXITCODE -ne 0) {
  throw "Docker Compose v2 is required."
}

$ServerOs = docker version --format '{{.Server.Os}}'
$ServerArch = docker version --format '{{.Server.Arch}}'
if ($ServerOs -ne "linux") {
  throw "This package requires Docker Linux containers."
}
if ($ServerArch -ne "amd64" -and $ServerArch -ne "x86_64") {
  throw "This is the Windows x64 package; Docker reports architecture '$ServerArch'."
}

$ImageTag = "paper-monitor:v0.1.0"
docker image inspect $ImageTag | Out-Null
if ($LASTEXITCODE -ne 0) {
  docker load -i ".\images\paper-monitor-v0.1.0-linux-amd64.tar.gz"
}

$ImageArch = docker image inspect --format '{{.Architecture}}' $ImageTag
if ($ImageArch -ne "amd64") {
  throw "Image '$ImageTag' is '$ImageArch', not amd64. Remove or retag it manually before continuing."
}

New-Item -ItemType Directory -Force -Path config, data, output | Out-Null

if ($Mode -eq "setup") {
  docker compose -f compose.yaml run --rm -it rss-paper Rscript Paper_Monitor.R
  exit $LASTEXITCODE
}

docker compose -f compose.yaml up --no-build rss-paper
exit $LASTEXITCODE
