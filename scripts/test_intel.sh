#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
derived_data="${DERIVED_DATA_PATH:-$repo_root/build/intel-macos/UnitDerivedData}"

if [[ "$(/usr/bin/uname -m)" != "x86_64" ]]; then
  echo "Native Intel tests require an x86_64 macOS host." >&2
  exit 1
fi

/usr/bin/xcodebuild \
  -project "$repo_root/app/macOS/EPUBTranslator.xcodeproj" \
  -scheme EPUBTranslator \
  -configuration Debug \
  -destination 'platform=macOS,arch=x86_64' \
  -derivedDataPath "$derived_data" \
  -only-testing:EPUBTranslatorTests \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  ENABLE_TESTABILITY=YES \
  SWIFT_OPTIMIZATION_LEVEL=-Onone \
  COMPILER_INDEX_STORE_ENABLE=NO \
  ARCHS=x86_64 \
  ONLY_ACTIVE_ARCH=YES \
  test

echo "INTEL_NATIVE_TESTS=PASS"
