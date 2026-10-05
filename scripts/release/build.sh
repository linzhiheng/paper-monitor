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
  release scripts/release tests
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
[[ ! -e "$package_dir" && ! -e "$zip_path" && ! -e "$outer_checksum" ]] || fail "release output already exists in dist/"

mkdir -p "$dist_dir"
work_dir="$(mktemp -d "$dist_dir/.build.XXXXXX")"
cleanup() { rm -rf "$work_dir"; }
trap cleanup EXIT
mkdir -p "$work_dir/images" "$package_dir/images" "$package_dir/config" "$package_dir/data" "$package_dir/output" "$package_dir/reports"

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

cp "$work_dir/images/"*.tar.gz "$package_dir/images/"
cp config/template.md "$package_dir/config/template.md"
touch "$package_dir/data/.gitkeep" "$package_dir/output/.gitkeep"
cp LICENSE .env.example "$package_dir/"
cp release/README.md "$package_dir/README.md"
cp release/INSTALL_AND_USAGE.md "$package_dir/"
cp release/paper-monitor-macos-arm64.sh "$package_dir/"
cp release/paper-monitor-windows-amd64.ps1 "$package_dir/"
cp release/paper-monitor-windows-amd64.cmd "$package_dir/"
chmod 0755 "$package_dir/paper-monitor-macos-arm64.sh"
sed "s|__IMAGE_TAG__|$image_tag|g" release/compose.yaml.template > "$package_dir/compose.yaml"
cp release/security-exceptions.csv "$package_dir/reports/security-exceptions.csv"
cp release/security-policy.md "$package_dir/reports/security-policy.md"

if find "$package_dir/config" -type f ! -name template.md -print -quit | grep -q .; then
  fail "package config directory contains a non-template file"
fi

scripts/release/verify.sh --artifact-dir "$work_dir" --package-dir "$package_dir" --version "$version"

(
  cd "$package_dir"
  find . -type f ! -name SHA256SUMS -print | LC_ALL=C sort | while IFS= read -r file; do
    shasum -a 256 "$file"
  done > SHA256SUMS
)

(
  cd "$dist_dir"
  zip -qr "$zip_path" "$release_name"
)
( cd "$dist_dir" && shasum -a 256 "$release_name.zip" ) > "$outer_checksum"

echo "Release package: $zip_path"
echo "ZIP checksum: $outer_checksum"
