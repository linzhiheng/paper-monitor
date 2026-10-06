param(
  [Parameter(Mandatory = $true, Position = 0)]
  [ValidateSet("setup", "run", "uninstall")]
  [string]$Mode
)

$ErrorActionPreference = "Stop"
$RootDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $RootDir
$ImageTag = "paper-monitor:v0.1.1"

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

if ($Mode -eq "uninstall") {
  Write-Host "Stopping Paper Monitor and removing its Docker resources..."
  docker compose -f compose.yaml down --remove-orphans
  if ($LASTEXITCODE -ne 0) {
    throw "Docker Compose could not remove the Paper Monitor resources."
  }

  docker image inspect $ImageTag *> $null
  if ($LASTEXITCODE -eq 0) {
    docker image rm $ImageTag
    if ($LASTEXITCODE -ne 0) {
      throw "Docker could not remove image '$ImageTag'."
    }
    Write-Host "Removed Docker image: $ImageTag"
  }
  else {
    Write-Host "Docker image is already absent: $ImageTag"
  }

  $KeepAnswer = Read-Host "Keep settings, history, and output in config/, data/, and output/? [Y/n]"
  if ($KeepAnswer -match '^(n|no)$') {
    $Confirmation = Read-Host "Type DELETE to permanently remove config/, data/, and output/"
    if ($Confirmation -ceq "DELETE") {
      foreach ($Name in @("config", "data", "output")) {
        $Target = Join-Path $RootDir $Name
        if (Test-Path -LiteralPath $Target) {
          $Item = Get-Item -LiteralPath $Target -Force
          if (($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            Remove-Item -LiteralPath $Target -Force
          }
          else {
            Remove-Item -LiteralPath $Target -Recurse -Force
          }
        }
      }
      Write-Host "Removed settings, history, and output."
    }
    else {
      Write-Host "Data cleanup cancelled; config/, data/, and output/ were kept."
    }
  }
  else {
    Write-Host "Kept config/, data/, and output/."
  }

  Write-Host "Paper Monitor is uninstalled. The package files remain available for reinstallation."
  exit 0
}

$ServerOs = docker version --format '{{.Server.Os}}'
$ServerArch = docker version --format '{{.Server.Arch}}'
if ($ServerOs -ne "linux") {
  throw "This package requires Docker Linux containers."
}
if ($ServerArch -ne "amd64" -and $ServerArch -ne "x86_64") {
  throw "This is the Windows x64 package; Docker reports architecture '$ServerArch'."
}

docker image inspect $ImageTag | Out-Null
if ($LASTEXITCODE -ne 0) {
  docker load -i ".\images\paper-monitor-v0.1.1-linux-amd64.tar.gz"
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
