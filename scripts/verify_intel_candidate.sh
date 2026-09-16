#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
output_dir="${INTEL_CANDIDATE_OUTPUT_DIR:-$repo_root/release/intel-macos-candidate}"
zip_path="$(/usr/bin/find "$output_dir" -maxdepth 1 -type f -name '*-macOS-Intel.zip' -print -quit)"
dmg_path="$(/usr/bin/find "$output_dir" -maxdepth 1 -type f -name '*-macOS-Intel.dmg' -print -quit)"
expected_manifest="$(/usr/bin/find "$output_dir" -maxdepth 1 -type f -name '*-app-bundle-manifest.txt' -print -quit)"
temporary="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/epub-intel-verify.XXXXXX")"
zip_extract="$temporary/zip"
dmg_mount="$temporary/dmg"
dmg_attached=0
launch_app_pid=""
launch_executable=""

candidate_pids() {
  [[ -n "$launch_executable" ]] || return 0
  /bin/ps -axo pid=,command= | /usr/bin/awk -v expected="$launch_executable" \
    '$2 == expected { print $1 }'
}

candidate_pid_is_running() {
  local pid="$1"
  candidate_pids | /usr/bin/awk -v expected_pid="$pid" '$1 == expected_pid { found = 1 } END { exit !found }'
}

cleanup() {
  if [[ -n "$launch_app_pid" ]] && candidate_pid_is_running "$launch_app_pid"; then
    /bin/kill -TERM "$launch_app_pid" 2>/dev/null || true
  fi
  if [[ "$dmg_attached" -eq 1 ]]; then
    /usr/bin/hdiutil detach "$dmg_mount" -quiet || true
  fi
  /bin/rm -rf "$temporary"
}
trap cleanup EXIT

test -f "$zip_path"
test -f "$dmg_path"
test -f "$expected_manifest"
/bin/mkdir -p "$zip_extract" "$dmg_mount"
/usr/bin/ditto -x -k "$zip_path" "$zip_extract"
/usr/bin/hdiutil attach -quiet -readonly -nobrowse -mountpoint "$dmg_mount" "$dmg_path"
dmg_attached=1

zip_app="$(/usr/bin/find "$zip_extract" -type d -name 'EPUB翻译.app' -print -quit)"
dmg_app="$(/usr/bin/find "$dmg_mount" -maxdepth 2 -type d -name 'EPUB翻译.app' -print -quit)"
test -d "$zip_app"
test -d "$dmg_app"

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

canonical_bundle_manifest "$zip_app" > "$temporary/zip-manifest.txt"
canonical_bundle_manifest "$dmg_app" > "$temporary/dmg-manifest.txt"
/usr/bin/cmp "$expected_manifest" "$temporary/zip-manifest.txt"
/usr/bin/cmp "$expected_manifest" "$temporary/dmg-manifest.txt"

verify_bundle() {
  local app="$1"
  /usr/bin/codesign --verify --deep --strict --verbose=2 "$app"
  while IFS= read -r item; do
    if /usr/bin/file -b "$item" | /usr/bin/grep -q '^Mach-O'; then
      local architectures
      architectures="$(/usr/bin/lipo -archs "$item")"
      if [[ "$architectures" != "x86_64" ]]; then
        echo "Unexpected architecture in package: $item ($architectures)" >&2
        exit 1
      fi
    fi
  done < <(/usr/bin/find "$app" -type f -print)
}

verify_bundle "$zip_app"
verify_bundle "$dmg_app"

if /usr/bin/find "$zip_extract" "$dmg_mount" \
  \( -name '.git' -o -name '*.swift' -o -name '*.xcodeproj' -o -name '*.xcworkspace' \
     -o -name '*.dSYM' -o -name '*.epub' -o -name '*.log' -o -name '*.sqlite' \
     -o -name '*.sqlite3' -o -name '*.db' -o -name '*.checkpoint' \) -print | /usr/bin/grep -q .; then
  echo "Forbidden source, debug, user-data, or runtime file found in candidate." >&2
  exit 1
fi

private_path_pattern='/(Users|home)/[^/[:space:]]+'
secret_pattern='gh[pousr]_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{16,}'
if /usr/bin/grep -R -a -E "$private_path_pattern|$secret_pattern" \
  "$zip_extract" "$dmg_mount" >/dev/null 2>&1; then
  echo "Private path or secret-like content found in candidate." >&2
  exit 1
fi

/usr/bin/hdiutil detach "$dmg_mount" -quiet
dmg_attached=0

launch_app="$(cd "$(/usr/bin/dirname "$zip_app")" && /bin/pwd -P)/$(/usr/bin/basename "$zip_app")"
launch_executable="$launch_app/Contents/MacOS/EPUB翻译"
launch_log="$temporary/launch.log"
if ! /usr/bin/open -n "$launch_app" >"$launch_log" 2>&1; then
  /bin/cat "$launch_log" >&2
  echo "LaunchServices rejected the candidate app." >&2
  exit 1
fi

for _ in {1..15}; do
  launch_app_pid="$(candidate_pids | /usr/bin/awk 'NR == 1 { first = $1 } END { print first }')"
  if [[ -n "$launch_app_pid" ]]; then
    break
  fi
  /bin/sleep 1
done

if [[ -z "$launch_app_pid" ]]; then
  /bin/cat "$launch_log" >&2
  echo "Candidate app did not start within 15 seconds." >&2
  exit 1
fi

for _ in {1..4}; do
  /bin/sleep 1
  if ! candidate_pid_is_running "$launch_app_pid"; then
    /bin/cat "$launch_log" >&2
    echo "Candidate app did not remain running during launch smoke." >&2
    exit 1
  fi
done

/bin/kill -TERM "$launch_app_pid"
for _ in {1..10}; do
  if ! candidate_pid_is_running "$launch_app_pid"; then
    break
  fi
  /bin/sleep 1
done
if candidate_pid_is_running "$launch_app_pid"; then
  /bin/kill -KILL "$launch_app_pid" 2>/dev/null || true
  echo "Candidate app did not exit within 10 seconds." >&2
  exit 1
fi
launch_app_pid=""

orphan_process_count="$(candidate_pids | /usr/bin/awk 'END { print NR + 0 }')"
if [[ "$orphan_process_count" -ne 0 ]]; then
  echo "Candidate left $orphan_process_count matching process(es) after exit." >&2
  exit 1
fi

if [[ -d "$dmg_mount/EPUB翻译.app" ]]; then
  echo "DMG remained mounted after verification." >&2
  exit 1
fi

echo "PACKAGED_APP_MATCHES_TESTED_APP=YES"
echo "CODESIGN_VERIFY=PASS"
echo "PRIVATE_PATH_SCAN=PASS"
echo "SECRET_SCAN=PASS"
echo "USER_DATA_SCAN=PASS"
echo "INTEL_ZIP_SMOKE=PASS"
echo "INTEL_DMG_SMOKE=PASS"
echo "INTEL_CANDIDATE_APP_LAUNCH=PASS"
echo "INTEL_CANDIDATE_APP_PROCESS_DETECTED=PASS"
echo "INTEL_CANDIDATE_STAYS_RUNNING=PASS"
echo "INTEL_CANDIDATE_CLEAN_EXIT=PASS"
echo "INTEL_CANDIDATE_ORPHAN_PROCESS_COUNT=0"
