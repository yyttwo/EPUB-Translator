#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
project="$repo_root/app/macOS/EPUBTranslator.xcodeproj"
derived_data="${DERIVED_DATA_PATH:-$repo_root/build/intel-macos/ReleaseDerivedData}"
output_dir="${INTEL_APP_OUTPUT_DIR:-$repo_root/build/intel-macos/release}"
source_app="$derived_data/Build/Products/Release/EPUB翻译.app"
output_app="$output_dir/EPUB翻译.app"

/bin/mkdir -p "$derived_data" "$output_dir"

/usr/bin/xcodebuild \
  -project "$project" \
  -scheme EPUBTranslator \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$derived_data" \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  COMPILER_INDEX_STORE_ENABLE=NO \
  INFOPLIST_KEY_NSHumanReadableCopyright='Copyright © 2026 EPUB Translator. All rights reserved.' \
  ARCHS=x86_64 \
  ONLY_ACTIVE_ARCH=YES \
  build

test -d "$source_app"
/bin/rm -rf "$output_app"
/usr/bin/ditto "$source_app" "$output_app"

main_executable="$output_app/Contents/MacOS/EPUB翻译"
helper_executable="$output_app/Contents/Helpers/EPUBTranslatorHelper"
test -x "$main_executable"
test -x "$helper_executable"

verify_x86_64_only() {
  local executable="$1"
  local architectures
  architectures="$(/usr/bin/lipo -archs "$executable")"
  if [[ "$architectures" != "x86_64" ]]; then
    echo "Unexpected architecture for $executable: $architectures" >&2
    exit 1
  fi
}

verify_x86_64_only "$main_executable"
verify_x86_64_only "$helper_executable"

while IFS= read -r bundled_file; do
  if /usr/bin/file -b "$bundled_file" | /usr/bin/grep -q '^Mach-O'; then
    verify_x86_64_only "$bundled_file"
  fi
done < <(/usr/bin/find "$output_app" -type f -print)

/usr/bin/codesign --verify --deep --strict --verbose=2 "$output_app"

echo "INTEL_RELEASE_BUILD=PASS"
echo "INTEL_APP_PATH=$output_app"
echo "MAIN_EXECUTABLE_ARCHS=$(/usr/bin/lipo -archs "$main_executable")"
echo "HELPER_ARCHS=$(/usr/bin/lipo -archs "$helper_executable")"
echo "ALL_BUNDLED_EXECUTABLES_SUPPORT_X86_64=YES"
