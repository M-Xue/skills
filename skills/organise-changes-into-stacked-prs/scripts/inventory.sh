#!/usr/bin/env bash
# inventory.sh — per-file change inventory for planning a stacked split.
#
# Usage: inventory.sh [base-ref]
#   base-ref defaults to origin/<default branch> (via gh), falling back to origin/master.
#
# Compares base-ref to the working tree (committed + staged + unstaged changes), lists untracked
# files too, and prints: added / deleted / total lines per file sorted by size, a flag for
# generated-looking files, subtotals per top-level directory, and a grand total.
set -euo pipefail

base="${1:-}"
if [[ -z "$base" ]]; then
  trunk=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null || true)
  base="origin/${trunk:-master}"
fi

if ! git rev-parse --verify --quiet "$base" >/dev/null; then
  echo "error: base ref '$base' not found. Run 'git fetch origin' or pass a ref." >&2
  exit 1
fi

# Patterns whose lines inflate the count without adding review load.
gen_re='(^|/)(package-lock\.json|yarn\.lock|pnpm-lock\.yaml|Cargo\.lock|go\.sum|Gemfile\.lock|poetry\.lock|.*\.lock)$|(^|/)(__snapshots__|generated|gen|node_modules|dist|build)/|\.(snap|pb\.go|pb\.ts|generated\.[a-z]+|min\.js|min\.css)$|_pb2\.py$'

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

# Tracked changes: base vs working tree. Binary files show as "-", counted as 0.
git diff --numstat "$base" -- | awk -v OFS='\t' '{a=($1=="-")?0:$1; d=($2=="-")?0:$2; print a, d, $3}' >> "$tmp"

# Untracked files: everything is an addition.
while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  n=$(wc -l < "$f" | tr -d ' ')
  printf '%s\t0\t%s\n' "$n" "$f" >> "$tmp"
done < <(git ls-files --others --exclude-standard)

if [[ ! -s "$tmp" ]]; then
  echo "No changes relative to $base."
  exit 0
fi

echo "Changes relative to $base (working tree, including uncommitted and untracked)"
echo
printf '%7s %7s %7s  %-4s %s\n' "added" "deleted" "total" "flag" "file"
sort -t$'\t' -k1,1nr -k2,2nr "$tmp" \
  | awk -F'\t' -v re="$gen_re" '
      { t=$1+$2; flag = ($3 ~ re) ? "GEN" : ""; printf "%7d %7d %7d  %-4s %s\n", $1, $2, t, flag, $3 }' \
  | sort -k3,3nr

echo
echo "Subtotals by top-level directory:"
awk -F'\t' '{ split($3, p, "/"); dir = (length(p) > 1) ? p[1] "/" : "(root)"; s[dir] += $1+$2; c[dir]++ }
            END { for (d in s) printf "%7d lines %4d files  %s\n", s[d], c[d], d }' "$tmp" | sort -nr

echo
awk -F'\t' -v re="$gen_re" '
  { t=$1+$2; total+=t; files++; if ($3 ~ re) { gen+=t; genf++ } }
  END {
    printf "Total: %d changed lines across %d files", total, files
    if (gen > 0) printf " (%d lines in %d generated-looking files)", gen, genf
    printf "\n"
    printf "At ~300 lines per PR that is roughly %d PRs; hard ceiling is 500 per PR.\n", (total - gen + 299) / 300
  }' "$tmp"
