#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "release build: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

root_dir="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root_dir"

for command in docker git gzip shasum zip; do require_command "$command"; done
docker buildx version >/dev/null 2>&1 || fail "Docker Buildx is required"

version="$(awk -F': *' '$1 == "Version" { print $2; exit }' DESCRIPTION)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "DESCRIPTION must contain a semantic Version"
tag="v$version"
image_tag="paper-monitor:$tag"

head_commit="$(git rev-parse HEAD)"
tag_commit="$(git rev-parse "$tag^{commit}" 2>/dev/null || true)"
[[ "$head_commit" == "$tag_commit" ]] || fail "HEAD must be exactly tagged $tag"

release_paths=(
  .dockerignore .env.example .gitignore DESCRIPTION Dockerfile LICENSE
  Paper_Monitor.R README.md R config/template.md docker-compose.yml renv.lock
  release scripts/release
)
for path in "${release_paths[@]}"; do
  git ls-files --error-unmatch "$path" >/dev/null 2>&1 || fail "release path is not tracked: $path"
done
git diff --quiet HEAD -- "${release_paths[@]}" || fail "release files have unstaged changes"
git diff --cached --quiet -- "${release_paths[@]}" || fail "release files have staged changes"

dist_dir="$root_dir/dist"
release_name="PaperMonitor-v$version-offline"
package_dir="$dist_dir/$release_name"
zip_path="$dist_dir/$release_name.zip"
outer_checksum="$zip_path.sha256"
macos_name="PaperMonitor-v$version-macos-arm64"
windows_name="PaperMonitor-v$version-windows-amd64"
[[ ! -e "$package_dir" && ! -e "$zip_path" && ! -e "$outer_checksum" \
   && ! -e "$dist_dir/$macos_name" && ! -e "$dist_dir/$macos_name.zip" \
   && ! -e "$dist_dir/$windows_name" && ! -e "$dist_dir/$windows_name.zip" ]] \
  || fail "release output already exists in dist/"

mkdir -p "$dist_dir"
work_dir="$(mktemp -d "$dist_dir/.build.XXXXXX")"
cleanup() { rm -rf "$work_dir"; }
trap cleanup EXIT
mkdir -p "$work_dir/images"

revision="$(git rev-parse --short=12 HEAD)"
build_date="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

build_platform() {
  local arch="$1"
  local archive="$work_dir/images/paper-monitor-v$version-linux-$arch.tar"

  docker buildx build \
    --platform "linux/$arch" \
    --build-arg "VERSION=$version" \
    --build-arg "VCS_REF=$revision" \
    --build-arg "BUILD_DATE=$build_date" \
    --tag "$image_tag" \
    --output "type=docker,dest=$archive" \
    "$root_dir"
  gzip -9 "$archive"
}

build_platform arm64
build_platform amd64

assemble_package() {
  local pkg_dir="$1"
  local platform="$2"
  mkdir -p "$pkg_dir/images" "$pkg_dir/config" "$pkg_dir/data" "$pkg_dir/output" "$pkg_dir/reports"
  cp config/template.md "$pkg_dir/config/template.md"
  touch "$pkg_dir/data/.gitkeep" "$pkg_dir/output/.gitkeep"
  cp LICENSE .env.example "$pkg_dir/"
  cp release/INSTALL_AND_USAGE.md "$pkg_dir/"
  cp release/security-exceptions.csv "$pkg_dir/reports/security-exceptions.csv"
  cp release/security-policy.md "$pkg_dir/reports/security-policy.md"
  sed "s|__IMAGE_TAG__|$image_tag|g" release/compose.yaml.template > "$pkg_dir/compose.yaml"

  local description
  case "$platform" in
    universal)
      description="Package: macOS (Apple Silicon) and Windows 11 x64 — contains both image archives and all launchers"
      cp "$work_dir/images/"*.tar.gz "$pkg_dir/images/"
      cp release/paper-monitor-macos-arm64.sh release/paper-monitor-windows-amd64.ps1 release/paper-monitor-windows-amd64.cmd "$pkg_dir/"
      chmod 0755 "$pkg_dir/paper-monitor-macos-arm64.sh"
      ;;
    macos-arm64)
      description="Package: macOS (Apple Silicon) — contains the arm64 image archive and the macOS launcher"
      cp "$work_dir/images/paper-monitor-v$version-linux-arm64.tar.gz" "$pkg_dir/images/"
      cp release/paper-monitor-macos-arm64.sh "$pkg_dir/"
      chmod 0755 "$pkg_dir/paper-monitor-macos-arm64.sh"
      ;;
    windows-amd64)
      description="Package: Windows 11 x64 — contains the amd64 image archive and the Windows launcher"
      cp "$work_dir/images/paper-monitor-v$version-linux-amd64.tar.gz" "$pkg_dir/images/"
      cp release/paper-monitor-windows-amd64.ps1 release/paper-monitor-windows-amd64.cmd "$pkg_dir/"
      ;;
  esac
  sed "s|__PACKAGE_DESCRIPTION__|$description|g" release/README.md > "$pkg_dir/README.md"

  if find "$pkg_dir/config" -type f ! -name template.md -print -quit | grep -q .; then
    fail "package config directory contains a non-template file"
  fi
}

write_sha256_sums() {
  local pkg_dir="$1"
  (
    cd "$pkg_dir"
    find . -type f ! -name SHA256SUMS -print | LC_ALL=C sort | while IFS= read -r file; do
      shasum -a 256 "$file"
    done > SHA256SUMS
  )
}

make_zip() {
  local pkg_dir="$1"
  local zip_name="$2"
  local checksum_file="$dist_dir/$zip_name.sha256"
  (
    cd "$dist_dir"
    zip -qr "$zip_name" "$(basename "$pkg_dir")" >/dev/null
  )
  ( cd "$dist_dir" && shasum -a 256 "$zip_name" ) > "$checksum_file"
  echo "$dist_dir/$zip_name (+ $checksum_file)"
}

assemble_package "$package_dir" universal

scripts/release/verify.sh --artifact-dir "$work_dir" --package-dir "$package_dir" --version "$version"

# Platform packages are pure subsets of the verified universal package
# (same image archives, launchers, and documentation), assembled after
# verification, so they need no separate image rebuild or test pass.
macos_package_dir="$dist_dir/$macos_name"
windows_package_dir="$dist_dir/$windows_name"
assemble_package "$macos_package_dir" macos-arm64
assemble_package "$windows_package_dir" windows-amd64

write_sha256_sums "$package_dir"
write_sha256_sums "$macos_package_dir"
write_sha256_sums "$windows_package_dir"

echo "Release packages:"
make_zip "$package_dir" "$release_name.zip"
make_zip "$macos_package_dir" "$macos_name.zip"
make_zip "$windows_package_dir" "$windows_name.zip"
