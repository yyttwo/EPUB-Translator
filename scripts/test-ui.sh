#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
derived_data="${DERIVED_DATA_PATH:-$repo_root/build/DerivedData}"
host_arch="$(/usr/bin/uname -m)"

/usr/bin/xcodebuild \
  -project "$repo_root/app/macOS/EPUBTranslator.xcodeproj" \
  -scheme EPUBTranslator \
  -configuration Debug \
  -destination "platform=macOS,arch=$host_arch" \
  -derivedDataPath "$derived_data" \
  -only-testing:EPUBTranslatorUITests/LocalAcceptanceUITests \
  -parallel-testing-enabled NO \
  -retry-tests-on-failure \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGNING_ALLOWED=YES \
  ENABLE_TESTABILITY=YES \
  SWIFT_OPTIMIZATION_LEVEL=-Onone \
  ARCHS="$host_arch" \
  ONLY_ACTIVE_ARCH=YES \
  test
