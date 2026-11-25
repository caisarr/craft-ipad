#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="${DIST:-$ROOT/dist}"
WORK="$ROOT/build/ios-package"
IPA_PATH="$DIST/CraftSuite-iPad-unsigned.ipa"

SKIP_FETCH="false"
if [[ "${1:-}" == "--skip-fetch" ]]; then
  SKIP_FETCH="true"
fi

if [[ "$SKIP_FETCH" != "true" ]]; then
  bash "$ROOT/scripts/fetch-web-bundles.sh"
fi

command -v xcodegen >/dev/null || { echo "error: xcodegen is required (brew install xcodegen)" >&2; exit 1; }
command -v xcodebuild >/dev/null || { echo "error: xcodebuild is required (Xcode on macOS)" >&2; exit 1; }

echo "==> Generating Xcode project via XcodeGen"
(cd "$ROOT/ios" && xcodegen generate --spec project.yml)

rm -rf "$WORK"
mkdir -p "$WORK" "$DIST"

echo "==> Building unsigned iOS archive"
xcodebuild \
  -project "$ROOT/ios/CraftSuite.xcodeproj" \
  -scheme CraftSuite \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -archivePath "$WORK/CraftSuite.xcarchive" \
  archive \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY=""

APP_PATH="$WORK/CraftSuite.xcarchive/Products/Applications/CraftSuite.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "error: archive did not produce CraftSuite.app" >&2
  exit 1
fi

echo "==> Packaging unsigned .ipa"
mkdir -p "$WORK/ipa/Payload"
ditto "$APP_PATH" "$WORK/ipa/Payload/CraftSuite.app"
rm -f "$IPA_PATH"
(cd "$WORK/ipa" && zip -qry "$IPA_PATH" Payload)

(cd "$DIST" && shasum -a 256 "$(basename "$IPA_PATH")" > SHA256SUMS.txt)
echo "==> Done: $IPA_PATH"
ls -lh "$DIST"
