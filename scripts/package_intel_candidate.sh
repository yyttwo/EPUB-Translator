#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
app_path="${INTEL_APP_PATH:-$repo_root/build/intel-macos/release/EPUB翻译.app}"
output_dir="${INTEL_CANDIDATE_OUTPUT_DIR:-$repo_root/release/intel-macos-candidate}"
source_commit="${SOURCE_COMMIT:-unknown}"

test -d "$app_path"
/bin/mkdir -p "$output_dir"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_path/Contents/Info.plist")"
base_name="EPUB-Translator-v${version}-macOS-Intel"
staging_root="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/epub-intel-package.XXXXXX")"
staging_dir="$staging_root/$base_name"
zip_path="$output_dir/$base_name.zip"
dmg_path="$output_dir/$base_name.dmg"
bundle_manifest="$output_dir/$base_name-app-bundle-manifest.txt"
manifest_path="$output_dir/$base_name-manifest.json"
checksums_path="$output_dir/SHA256SUMS.txt"
mounted_path="$staging_root/mounted"

cleanup() {
  if /sbin/mount | /usr/bin/grep -Fq " on $mounted_path "; then
    /usr/bin/hdiutil detach "$mounted_path" -quiet || true
  fi
  /bin/rm -rf "$staging_root"
}
trap cleanup EXIT

/bin/mkdir -p "$staging_dir"
/usr/bin/ditto "$app_path" "$staging_dir/EPUB翻译.app"
for notice in LICENSE NOTICE THIRD_PARTY_NOTICES.md; do
  if [[ -f "$repo_root/$notice" ]]; then
    /bin/cp "$repo_root/$notice" "$staging_dir/$notice"
  fi
done

canonical_bundle_manifest() {
  local bundle="$1"
  while IFS= read -r item; do
    local relative="${item#$bundle/}"
    if [[ -L "$item" ]]; then
      printf 'L  %s  %s\n' "$(/bin/readlink "$item")" "$relative"
    elif [[ -f "$item" ]]; then
      printf 'F  %s  %s\n' "$(/usr/bin/shasum -a 256 "$item" | /usr/bin/awk '{print $1}')" "$relative"
    fi
  done < <(/usr/bin/find "$bundle" \( -type f -o -type l \) -print | LC_ALL=C /usr/bin/sort)
}

canonical_bundle_manifest "$staging_dir/EPUB翻译.app" > "$bundle_manifest"
bundle_tree_sha256="$(/usr/bin/shasum -a 256 "$bundle_manifest" | /usr/bin/awk '{print $1}')"

/bin/rm -f "$zip_path" "$dmg_path" "$manifest_path" "$checksums_path"
(
  cd "$staging_root"
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$base_name" "$zip_path"
)
/usr/bin/hdiutil create \
  -quiet \
  -fs HFS+ \
  -format UDZO \
  -volname "EPUB翻译 Intel" \
  -srcfolder "$staging_dir" \
  "$dmg_path"

zip_sha256="$(/usr/bin/shasum -a 256 "$zip_path" | /usr/bin/awk '{print $1}')"
dmg_sha256="$(/usr/bin/shasum -a 256 "$dmg_path" | /usr/bin/awk '{print $1}')"

cat > "$manifest_path" <<EOF
{
  "product": "EPUB翻译",
  "version": "$version",
  "build": "$build",
  "target_os": "macOS",
  "target_architecture": "x86_64",
  "source_commit": "$source_commit",
  "minimum_macos": "13.0",
  "api_key_storage": "session_only",
  "real_api_requests": 0,
  "fixture": "self-authored",
  "developer_id_signed": false,
  "notarized": false,
  "app_bundle_tree_sha256": "$bundle_tree_sha256",
  "dmg_sha256": "$dmg_sha256",
  "zip_sha256": "$zip_sha256"
}
EOF

{
  printf '%s  %s\n' "$dmg_sha256" "$(basename "$dmg_path")"
  printf '%s  %s\n' "$zip_sha256" "$(basename "$zip_path")"
  printf '%s  %s\n' "$(/usr/bin/shasum -a 256 "$bundle_manifest" | /usr/bin/awk '{print $1}')" "$(basename "$bundle_manifest")"
  printf '%s  %s\n' "$(/usr/bin/shasum -a 256 "$manifest_path" | /usr/bin/awk '{print $1}')" "$(basename "$manifest_path")"
} > "$checksums_path"

echo "DMG_PATH=$dmg_path"
echo "ZIP_PATH=$zip_path"
echo "DMG_SHA256=$dmg_sha256"
echo "ZIP_SHA256=$zip_sha256"
echo "APP_BUNDLE_TREE_SHA256=$bundle_tree_sha256"
