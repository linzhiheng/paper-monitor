#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "release verify: $*" >&2
  exit 1
}

artifact_dir=""
package_dir=""
version=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --artifact-dir) artifact_dir="$2"; shift 2 ;;
    --package-dir) package_dir="$2"; shift 2 ;;
    --version) version="$2"; shift 2 ;;
    *) fail "unknown argument: $1" ;;
  esac
done

[[ -n "$artifact_dir" && -n "$package_dir" && -n "$version" ]] || fail "--artifact-dir, --package-dir, and --version are required"
[[ -d "$artifact_dir/images" && -d "$package_dir/reports" ]] || fail "release directories are incomplete"

root_dir="$(cd "$(dirname "$0")/../.." && pwd)"
# The test suite is intentionally not tracked in git; it must exist
# locally for the packaged-container test pass below.
[[ -d "$root_dir/tests" ]] || fail "tests directory is missing locally (the test suite is intentionally not tracked in git)"
# shellcheck source=/dev/null
source "$root_dir/release/tool-images.env"
[[ -n "${SYFT_IMAGE:-}" && -n "${TRIVY_IMAGE:-}" && -n "${HTTP_ECHO_IMAGE:-}" ]] || fail "tool image configuration is incomplete"

docker compose -f "$package_dir/compose.yaml" config --quiet

image_tag="paper-monitor:v$version"
required_packages='xml2,dplyr,purrr,httr2,jsonlite,tibble,stringr'

verify_image() {
  local arch="$1"
  local archive="$artifact_dir/images/paper-monitor-v$version-linux-$arch.tar.gz"
  [[ -f "$archive" ]] || fail "missing image archive: $archive"

  docker load -i "$archive" >/dev/null
  local image_arch
  image_arch="$(docker image inspect --format '{{.Architecture}}' "$image_tag")"
  [[ "$image_arch" == "$arch" ]] || fail "$image_tag loaded as $image_arch instead of $arch"
  local platform_tag="$image_tag-$arch"
  docker tag "$image_tag" "$platform_tag"

  docker run --rm --platform "linux/$arch" --entrypoint Rscript "$platform_tag" -e "packages <- strsplit('$required_packages', ',', fixed = TRUE)[[1]]; missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]; if (length(missing)) stop(paste(missing, collapse = ', ')); cat('required R packages: PASS\\n')"

  docker run --rm --platform "linux/$arch" -v "$root_dir/tests:/app/tests:ro" --entrypoint sh "$platform_tag" -c 'sh tests/run_all.sh'

  local output status
  set +e
  output="$(docker run --rm --platform "linux/$arch" --tmpfs /app/config "$platform_tag" 2>&1)"
  status=$?
  set -e
  [[ $status -ne 0 ]] || fail "empty configuration unexpectedly succeeded on $arch"
  [[ "$output" == *"LLM connection is not configured"* ]] || fail "empty configuration did not report the expected LLM error on $arch"
}

verify_image arm64
verify_image amd64

mock_name="paper-monitor-ollama-mock-$$"
cleanup_mock() {
  docker rm -f "$mock_name" >/dev/null 2>&1 || true
}
trap cleanup_mock EXIT
docker run -d --rm --name "$mock_name" -p 127.0.0.1:18080:5678 "$HTTP_ECHO_IMAGE" -listen=:5678 -text=ok >/dev/null
sleep 1
docker run --rm --platform linux/arm64 --entrypoint Rscript "$image_tag-arm64" -e "source('R/config_layer.R'); source('R/llm_layer.R'); result <- test_llm_connection(list(backend = 'ollama', model = 'mock', url = 'http://host.docker.internal:18080/api/generate')); if (!isTRUE(result\$success)) stop(result\$message); cat('Ollama host route: PASS\\n')"

today="$(date +%F)"
make_ignore_file() {
  local platform="$1"
  local destination="$2"
  awk -F, -v platform="$platform" -v today="$today" '
    NR == 1 {
      if ($0 != "vulnerability_id,platform,reason,expires_on") {
        print "invalid security-exceptions.csv header" > "/dev/stderr"; exit 2
      }
      next
    }
    NF != 4 || $1 == "" || $2 == "" || $3 == "" || $4 !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ {
      print "invalid security exception at line " NR > "/dev/stderr"; exit 2
    }
    $4 < today {
      print "expired security exception at line " NR > "/dev/stderr"; exit 2
    }
    $2 == platform || $2 == "all" { print $1 }
  ' "$root_dir/release/security-exceptions.csv" > "$destination"
}

scan_archive() {
  local arch="$1"
  local archive_name="paper-monitor-v$version-linux-$arch.tar.gz"
  local archive="$artifact_dir/images/$archive_name"
  local scan_archive="$artifact_dir/images/paper-monitor-v$version-linux-$arch.tar"
  local sbom="$package_dir/reports/paper-monitor-v$version-linux-$arch.spdx.json"
  local report="$package_dir/reports/paper-monitor-v$version-linux-$arch.vulnerabilities.json"
  local ignore_file
  ignore_file="$(mktemp)"
  make_ignore_file "linux/$arch" "$ignore_file"
  gunzip -c "$archive" > "$scan_archive"

  docker run --rm -v "$artifact_dir/images:/artifacts:ro" "$SYFT_IMAGE" "docker-archive:/artifacts/$(basename "$scan_archive")" -o spdx-json > "$sbom"
  set +e
  docker run --rm \
    -v "$artifact_dir/images:/artifacts:ro" \
    -v "$package_dir/reports:/reports" \
    -v "$ignore_file:/policy/.trivyignore:ro" \
    "$TRIVY_IMAGE" image --input "/artifacts/$(basename "$scan_archive")" --scanners vuln --format json \
      --output "/reports/$(basename "$report")" --severity HIGH,CRITICAL \
      --ignore-unfixed --ignorefile /policy/.trivyignore --exit-code 1
  local scan_status=$?
  set -e
  rm -f "$ignore_file"
  rm -f "$scan_archive"
  [[ $scan_status -eq 0 ]] || fail "unapproved HIGH or CRITICAL vulnerability found in linux/$arch"
  [[ -s "$sbom" && -s "$report" ]] || fail "security reports were not generated for linux/$arch"
}

scan_archive arm64
scan_archive amd64

echo "release verification: PASS"
