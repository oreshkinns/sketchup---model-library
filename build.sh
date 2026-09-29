#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")" && pwd)"
staging_dir="$(mktemp -d)"
trap 'rm -rf "$staging_dir"' EXIT

mkdir -p "$staging_dir/maf_library" "$project_dir/dist"
cp "$project_dir/maf_library.rb" "$staging_dir/maf_library.rb"
cp "$project_dir/maf_library/"*.rb "$staging_dir/maf_library/"
cp "$project_dir/preview.html" "$staging_dir/maf_library/ui.html"
version="$(ruby -ne 'puts $1 if /VERSION = [\x27\x22]([^\x27\x22]+)[\x27\x22]/' "$project_dir/maf_library.rb" | head -n 1)"
test -n "$version"

(
  cd "$staging_dir"
  zip -q -r "$project_dir/dist/maf_library-$version.rbz" maf_library.rb maf_library
)

echo "$project_dir/dist/maf_library-$version.rbz"
