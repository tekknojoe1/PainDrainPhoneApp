#!/usr/bin/env bash
#
# Build release artifacts named with the app name + version, e.g.
#   dist/PainDrain_1.1.0_release.apk
#   dist/PainDrain_1.1.0_release.ipa
#
# The version is read from pubspec.yaml, so it stays in sync automatically.
#
# Usage:
#   scripts/build_release.sh [apk|ipa|all]   (default: all)
#
# Notes:
# - Android: `flutter build apk` also writes a versioned copy to
#   build/app/outputs/apk/release/ via android/app/build.gradle; this script
#   additionally collects it into dist/.
# - iOS: produces a local distribution IPA via `flutter build ipa`. This is a
#   local file for archiving/sharing and is separate from the TestFlight upload
#   flow (xcodebuild -exportArchive ... destination=upload). Run on macOS with
#   signing configured.

set -euo pipefail

cd "$(dirname "$0")/.."

APP="PainDrain"
VERSION="$(grep -E '^version:' pubspec.yaml | sed -E 's/^version:[[:space:]]*//' | cut -d'+' -f1)"
TARGET="${1:-all}"

mkdir -p dist

build_apk() {
  flutter build apk --release
  cp build/app/outputs/flutter-apk/app-release.apk \
    "dist/${APP}_${VERSION}_release.apk"
  echo "Wrote dist/${APP}_${VERSION}_release.apk"
}

build_ipa() {
  flutter build ipa --release
  local ipa
  ipa="$(ls -t build/ios/ipa/*.ipa 2>/dev/null | head -n 1 || true)"
  if [[ -z "${ipa}" ]]; then
    echo "No .ipa found in build/ios/ipa/ — the iOS build may have only" \
      "archived (signing/export needed). Skipping IPA rename." >&2
    return 0
  fi
  cp "${ipa}" "dist/${APP}_${VERSION}_release.ipa"
  echo "Wrote dist/${APP}_${VERSION}_release.ipa"
}

case "${TARGET}" in
  apk) build_apk ;;
  ipa) build_ipa ;;
  all) build_apk; build_ipa ;;
  *) echo "Usage: $0 [apk|ipa|all]" >&2; exit 1 ;;
esac
