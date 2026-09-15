#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
scratch_path="${SWIFT_SCRATCH_PATH:-$repo_root/build/intel-macos/SwiftPM}"

if [[ "$(/usr/bin/uname -m)" != "x86_64" ]]; then
  echo "Native Intel tests require an x86_64 macOS host." >&2
  exit 1
fi

cd "$repo_root"
/usr/bin/swift build \
  --scratch-path "$scratch_path" \
  --arch x86_64 \
  --product EPUBTranslatorHelper

bin_path="$(/usr/bin/swift build --scratch-path "$scratch_path" --arch x86_64 --show-bin-path)"
helper_path="$bin_path/EPUBTranslatorHelper"
test -x "$helper_path"
test "$(/usr/bin/lipo -archs "$helper_path")" = "x86_64"

EPUB_TRANSLATOR_TEST_HELPER_PATH="$helper_path" \
  /usr/bin/swift test \
    --scratch-path "$scratch_path" \
    --arch x86_64

echo "INTEL_NATIVE_TESTS=PASS"
