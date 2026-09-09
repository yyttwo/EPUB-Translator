#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
derived_data="${DERIVED_DATA_PATH:-$repo_root/build/DerivedData}"

/usr/bin/xcodebuild \
  -project "$repo_root/app/macOS/EPUBTranslator.xcodeproj" \
  -scheme EPUBTranslator \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:EPUBTranslatorTests \
  test
