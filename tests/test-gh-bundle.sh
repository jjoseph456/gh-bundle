#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/gh-bundle-test.XXXXXX")"
trap 'rm -rf "$TMPDIR"' EXIT

make_fixture() {
  local name="$1" percent="$2"
  mkdir -p "$TMPDIR/$name/metadata"
  cat > "$TMPDIR/$name/metadata/diagnostics.txt" <<EOF
Filesystem      Size  Used Avail Use% Mounted on
/dev/sda1       100G  10G  90G   ${percent}% /
Mem:            100  20  10  0  70  80
EOF
  printf '{"checks":[]}\n' > "$TMPDIR/$name/metadata/services_consul_status.json"
}

run_bundle() {
  local fixture="$1" output="$2"
  set +e
  "$ROOT/gh-bundle" "$TMPDIR/$fixture" --json > "$output"
  local code=$?
  set -e
  printf '%s' "$code"
}

make_fixture healthy 10
code="$(run_bundle healthy "$TMPDIR/healthy.json")"
[ "$code" -eq 0 ]
python3 - "$TMPDIR/healthy.json" <<'PY'
import json
import sys

result = json.load(open(sys.argv[1]))
assert result["verdict"] == "clean-first-look"
assert result["flags"] == 0
PY

make_fixture disk-warning 90
code="$(run_bundle disk-warning "$TMPDIR/disk-warning.json")"
[ "$code" -eq 2 ]
python3 - "$TMPDIR/disk-warning.json" <<'PY'
import json
import sys

result = json.load(open(sys.argv[1]))
assert result["verdict"] == "flags-raised"
assert result["flags"] == 1
assert any(
    finding["type"] == "disk"
    for node in result["nodes"]
    for finding in node["findings"]
)
PY
