#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
source_dir="$repo_root/fixtures/stage-1-source"
output="$repo_root/fixtures/stage-1-self-authored.epub"
temporary_directory="$(/usr/bin/mktemp -d)"
temporary_output="$temporary_directory/stage-1-self-authored.epub"
cleanup() { /bin/rm -rf "$temporary_directory"; }
trap cleanup EXIT

(
  cd "$source_dir"
  /usr/bin/zip -X -q -0 "$temporary_output" mimetype
  /usr/bin/zip -X -q -r -9 "$temporary_output" META-INF EPUB
)

/bin/mv "$temporary_output" "$output"
