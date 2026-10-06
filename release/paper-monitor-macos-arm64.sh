#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: ./paper-monitor-macos-arm64.sh {menu|run|uninstall}" >&2
  exit 64
}

mode="${1:-}"
[[ "$mode" == "menu" || "$mode" == "run" || "$mode" == "uninstall" ]] || usage

root_dir="$(cd "$(dirname "$0")" && pwd)"
cd "$root_dir"

image_tag="paper-monitor:v0.1.3"

command -v docker >/dev/null 2>&1 || { echo "Docker Desktop or OrbStack is required." >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "Docker is installed but its daemon is not running." >&2; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "Docker Compose v2 is required." >&2; exit 1; }

if [[ "$mode" == "uninstall" ]]; then
  echo "Stopping Paper Monitor and removing its Docker resources..."
  docker compose -f compose.yaml down --remove-orphans

  if docker image inspect "$image_tag" >/dev/null 2>&1; then
    docker image rm "$image_tag"
    echo "Removed Docker image: $image_tag"
  else
    echo "Docker image is already absent: $image_tag"
  fi

  keep_answer=""
  IFS= read -r -p "Keep settings, history, and output in config/, data/, and output/? [Y/n] " keep_answer || true
  case "$keep_answer" in
    n|N|no|NO|No)
      confirmation=""
      IFS= read -r -p "Type DELETE to permanently remove config/, data/, and output/: " confirmation || true
      if [[ "$confirmation" == "DELETE" ]]; then
        rm -rf -- "$root_dir/config" "$root_dir/data" "$root_dir/output"
        echo "Removed settings, history, and output."
      else
        echo "Data cleanup cancelled; config/, data/, and output/ were kept."
      fi
      ;;
    *)
      echo "Kept config/, data/, and output/."
      ;;
  esac

  echo "Paper Monitor is uninstalled. The package files remain available for reinstallation."
  exit 0
fi

server_os="$(docker version --format '{{.Server.Os}}')"
server_arch="$(docker version --format '{{.Server.Arch}}')"
[[ "$server_os" == "linux" ]] || { echo "This package requires Docker Linux containers." >&2; exit 1; }
[[ "$server_arch" == "arm64" || "$server_arch" == "aarch64" ]] || { echo "This is the macOS ARM64 package; Docker reports architecture '$server_arch'." >&2; exit 1; }

if ! docker image inspect "$image_tag" >/dev/null 2>&1; then
  docker load -i "images/paper-monitor-v0.1.3-linux-arm64.tar.gz"
fi

image_arch="$(docker image inspect --format '{{.Architecture}}' "$image_tag")"
[[ "$image_arch" == "arm64" ]] || { echo "Image '$image_tag' is '$image_arch', not arm64. Remove or retag it manually before continuing." >&2; exit 1; }

mkdir -p config data output

if [[ "$mode" == "menu" ]]; then
  exec docker compose -f compose.yaml run --rm -it rss-paper Rscript Paper_Monitor.R
fi

exec docker compose -f compose.yaml up --no-build rss-paper
