#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_DIR="$ROOT/ios/CraftSuite/WebBundle"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

GRIDCRAFT_VERSION="${GRIDCRAFT_VERSION:-latest}"
PDFCRAFT_VERSION="${PDFCRAFT_VERSION:-latest}"
WORDCRAFT_VERSION="${WORDCRAFT_VERSION:-latest}"

fetch_app() {
  local app="$1"
  local repo="$2"
  local requested_ver="$3"
  local fallback_ver="$4"
  local dest="$BUNDLE_DIR/$app"

  local api_url
  if [[ "$requested_ver" == "latest" || -z "$requested_ver" ]]; then
    api_url="https://api.github.com/repos/$repo/releases/latest"
  else
    api_url="https://api.github.com/repos/$repo/releases/tags/$requested_ver"
  fi

  echo "==> Resolving release for $repo ($requested_ver)..."
  local -a curl_headers=(-H "Accept: application/vnd.github+json" -H "User-Agent: craft-ipad-builder")
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    curl_headers+=(-H "Authorization: Bearer $GITHUB_TOKEN")
  fi

  local release_json=""
  if ! release_json="$(curl -fsSL "${curl_headers[@]}" "$api_url" 2>/dev/null)"; then
    if [[ "$requested_ver" == "latest" ]]; then
      echo "    warn: latest lookup failed, falling back to $fallback_ver"
      release_json="$(curl -fsSL "${curl_headers[@]}" "https://api.github.com/repos/$repo/releases/tags/$fallback_ver")"
    else
      echo "error: failed to fetch release metadata for $repo ($requested_ver)" >&2
      exit 1
    fi
  fi

  local asset_url
  asset_url="$(python3 -c '
import json, re, sys
data = json.load(sys.stdin)
app = sys.argv[1]
pat = re.compile(rf"^{re.escape(app)}-web-.*\.zip$")
for asset in data.get("assets", []):
    if pat.match(asset.get("name", "")):
        print(asset["browser_download_url"])
        sys.exit(0)
sys.exit(1)
' "$app" <<<"$release_json")"

  if [[ -z "$asset_url" ]]; then
    echo "error: could not find ${app}-web-*.zip in release for $repo" >&2
    exit 1
  fi

  local zip_path="$TMP_DIR/${app}.zip"
  local unpack_dir="$TMP_DIR/${app}_unpack"
  mkdir -p "$unpack_dir"

  echo "    downloading: $asset_url"
  curl -fsSL -L -o "$zip_path" "$asset_url"
  unzip -q "$zip_path" -d "$unpack_dir"

  local index_file
  index_file="$(find "$unpack_dir" -maxdepth 3 -name 'index.html' -print -quit)"
  if [[ -z "$index_file" ]]; then
    echo "error: index.html not found inside ${app}.zip" >&2
    exit 1
  fi
  local src_dir
  src_dir="$(dirname "$index_file")"

  rm -rf "$dest"
  mkdir -p "$dest"
  cp -R "$src_dir/." "$dest/"

  local wasm_count
  wasm_count="$(find "$dest" -maxdepth 2 -name '*.wasm' | wc -l | tr -d ' ')"
  if [[ ! -f "$dest/index.html" || "$wasm_count" -eq 0 ]]; then
    echo "error: bundle validation failed for $app (index.html or .wasm missing)" >&2
    exit 1
  fi

  echo "    installed $app -> $dest ($wasm_count wasm file(s))"
}

mkdir -p "$BUNDLE_DIR"
fetch_app "gridcraft" "storytold/gridcraft" "$GRIDCRAFT_VERSION" "v0.19.1"
fetch_app "pdfcraft"  "storytold/pdfcraft"  "$PDFCRAFT_VERSION"  "v0.22.0"
fetch_app "wordcraft" "storytold/wordcraft" "$WORDCRAFT_VERSION" "v0.18.1"

echo "All 3 web bundles ready under $BUNDLE_DIR"
