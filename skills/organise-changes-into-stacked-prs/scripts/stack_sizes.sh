#!/usr/bin/env bash
# stack_sizes.sh — changed lines and commit count per layer of the current gh stack.
#
# Usage: stack_sizes.sh [--target N] [--max N]
#   Defaults: --target 300 --max 500.
#
# Reads `gh stack view --json`, diffs each branch against the branch below it (or trunk), and
# prints a table. Layers over --target are marked WARN, over --max are marked OVER and the script
# exits 1 so it can gate a submit.
set -euo pipefail

target=300
max=500
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) target="$2"; shift 2 ;;
    --max) max="$2"; shift 2 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

json=$(gh stack view --json) || { echo "error: not in a gh stack (run from a stack branch)" >&2; exit 2; }

python3 -I - "$json" "$target" "$max" <<'PY'
import json, subprocess, sys

data = json.loads(sys.argv[1])
target, maximum = int(sys.argv[2]), int(sys.argv[3])
trunk = data["trunk"]
branches = [b for b in data.get("branches", [])]

def run(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True, check=True).stdout

def exists(ref):
    return subprocess.run(["git", "rev-parse", "--verify", "--quiet", ref],
                          capture_output=True).returncode == 0

# Prefer the remote trunk if it exists so the bottom layer is measured against what it targets.
base = f"origin/{trunk}" if exists(f"origin/{trunk}") else trunk

rows = []
over = False
total_lines = 0
parent = base
for b in branches:
    name = b["name"]
    if not exists(name):
        rows.append((name, parent, "-", "-", "missing locally"))
        parent = name
        continue
    added = deleted = 0
    for line in run("diff", "--numstat", parent, name).splitlines():
        a, d, _ = line.split("\t", 2)
        added += 0 if a == "-" else int(a)
        deleted += 0 if d == "-" else int(d)
    lines = added + deleted
    commits = run("rev-list", "--count", f"{parent}..{name}").strip()
    if b.get("isMerged"):
        status = "merged"
    elif lines > maximum:
        status, over = "OVER", True
    elif lines > target:
        status = "WARN"
    else:
        status = "ok"
    total_lines += lines
    rows.append((name, parent, f"{lines} (+{added}/-{deleted})", commits, status))
    parent = name

w = max(len(r[0]) for r in rows) if rows else 10
print(f"Stack on {trunk} (measured against {base}); target {target}, max {maximum}\n")
print(f"{'layer':<{w}}  {'lines':<22}  {'commits':>7}  status")
for name, _, lines, commits, status in rows:
    print(f"{name:<{w}}  {lines:<22}  {commits:>7}  {status}")
print(f"\nTotal: {total_lines} changed lines across {len(rows)} layers")
sys.exit(1 if over else 0)
PY
