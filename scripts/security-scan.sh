#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

fail=0

check_pattern() {
  local label="$1"
  local pattern="$2"
  local insensitive=0
  if [[ "$pattern" == '(?i)'* ]]; then
    insensitive=1
    pattern="${pattern#'(i)'}"
    pattern="${pattern#'(?i)'}"
  fi

  if command -v rg >/dev/null 2>&1; then
    local rg_options=(-n --hidden --glob '!.git/**' --glob '!build/**')
    if [[ "$insensitive" -eq 1 ]]; then
      rg_options+=(-i)
    fi
    if rg "${rg_options[@]}" "$pattern" .; then
      echo "FAILED: $label"
      fail=1
    else
      echo "PASS: $label"
    fi
    return
  fi

  local grep_options=(-n -E -I)
  if [[ "$insensitive" -eq 1 ]]; then
    grep_options+=(-i)
  fi
  local found=0
  while IFS= read -r -d '' candidate; do
    if /usr/bin/grep "${grep_options[@]}" "$pattern" "$candidate"; then
      found=1
    fi
  done < <(find . -type f -not -path './.git/*' -not -path './build/*' -print0)

  if [[ "$found" -eq 1 ]]; then
    echo "FAILED: $label"
    fail=1
  else
    echo "PASS: $label"
  fi
}

check_pattern "credential-like values" '(?i)(api[_ -]?key|password|passwd|authorization)[[:space:]]*[:=][[:space:]]*["'\'']?[A-Za-z0-9_./+:-]{12,}'
check_pattern "common secret formats" '(sk-[A-Za-z0-9_-]{16,}|AKIA[0-9A-Z]{16}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----)'
check_pattern "personal home paths" '/(Users|home)/[^/[:space:]"'\'']+'

release_files="$(find . -type f \( -name '*.app' -o -name '*.dmg' -o -name '*.zip' -o -name '*.dSYM' \) -not -path './build/*' -not -path './.git/*' -print)"
if [[ -n "$release_files" ]]; then
  echo "$release_files"
  echo "FAILED: release binaries"
  fail=1
else
  echo "PASS: no release binaries"
fi

runtime_files="$(find . -type f \( -name '*.sqlite' -o -name '*.sqlite3' -o -name '*.db' -o -name '*.checkpoint' -o -name '*.log' -o -name '*.xcresult' \) -not -path './build/*' -not -path './.git/*' -print)"
if [[ -n "$runtime_files" ]]; then
  echo "$runtime_files"
  echo "FAILED: runtime data"
  fail=1
else
  echo "PASS: no runtime data"
fi

unexpected_epubs="$(find . -type f -name '*.epub' -not -path './fixtures/stage-1-self-authored.epub' -not -path './build/*' -not -path './.git/*' -print)"
if [[ -n "$unexpected_epubs" ]]; then
  echo "$unexpected_epubs"
  echo "FAILED: unexpected EPUB files"
  fail=1
else
  echo "PASS: only the self-authored EPUB fixture is present"
fi

if find . -type l -not -path './.git/*' -print | grep -q .; then
  find . -type l -not -path './.git/*' -print
  echo "FAILED: symlinks"
  fail=1
else
  echo "PASS: no symlinks"
fi

if find . -type f -not -path './.git/*' -links +1 -print | grep -q .; then
  find . -type f -not -path './.git/*' -links +1 -print
  echo "FAILED: hardlinks"
  fail=1
else
  echo "PASS: no hardlinks"
fi

exit "$fail"
