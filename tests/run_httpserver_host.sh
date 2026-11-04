#!/usr/bin/env bash
set -euo pipefail

module_root="$(cd "$(dirname "$0")/.." && pwd)"
sdk="$(cd "$module_root/../.." && pwd)"
bmk="${BMX_BMK:-$sdk/bin/bmk}"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

"$bmk" makeapp -a -r -o "$work_dir/httpserver_host" \
    "$module_root/tests/httpserver_host.bmx"
python3 "$module_root/tests/test_httpserver_host.py" "$work_dir/httpserver_host"
