#!/usr/bin/env bash
# generate_pr_train_toc.sh — print the PR Train table-of-contents block for one PR in a stack.
#
# Usage:
#   generate_pr_train_toc.sh                          # from inside a gh stack: reads the stack,
#                                                     #   looks up each branch's PR, marks the current branch's PR
#   generate_pr_train_toc.sh --current <pr>           # same, but mark a different PR
#   generate_pr_train_toc.sh [--current <pr>] <pr>... # explicit PR ids, bottom to top (no gh stack needed)
#
# Ids may be 1103425, #1103425, or a PR URL. Needs gh, the gh-stack extension, and jq.
#
# Output only. Fetching the description, swapping any existing <pr-train-toc> block, and saving
# with `gh pr edit` are done by hand (see step 6 of SKILL.md).
set -euo pipefail

current=""
prs=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --current) current="$2"; shift 2 ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) prs+=("$1"); shift ;;
  esac
done

die() { echo "error: $*" >&2; exit 2; }
num() { local n; n=$(printf '%s' "$1" | grep -oE '[0-9]+$' || true); [[ -n "$n" ]] || die "cannot read a PR number from '$1'"; printf '%s' "$n"; }

ids=()
if [[ ${#prs[@]} -gt 0 ]]; then
  for p in "${prs[@]}"; do ids+=("$(num "$p")"); done
else
  command -v jq >/dev/null || die "jq is required to read the stack (brew install jq), or pass PR ids explicitly"
  stack=$(gh stack view --json 2>/dev/null) || die "not inside a gh stack; check out a stack branch or pass PR ids explicitly"
  branch=$(git branch --show-current)
  while IFS= read -r b; do
    [[ -n "$b" ]] || continue
    n=$(gh pr view "$b" --json number -q .number 2>/dev/null) || die "branch '$b' has no PR yet; run 'gh stack submit' first"
    ids+=("$n")
    [[ -z "$current" && "$b" == "$branch" ]] && current="$n"
  done < <(jq -r '.branches[] | select(.isMerged | not) | .name' <<<"$stack")
  [[ ${#ids[@]} -gt 0 ]] || die "the current stack has no unmerged branches"
fi

[[ -z "$current" ]] || current=$(num "$current")
if [[ -n "$current" ]]; then
  found=0; for i in "${ids[@]}"; do [[ "$i" == "$current" ]] && found=1; done
  [[ $found -eq 1 ]] || die "--current #$current is not in the train"
fi

printf '<pr-train-toc>\n\n### 🚂 PR Train \n'
for i in "${ids[@]}"; do
  if [[ "$i" == "$current" ]]; then printf '1. #%s  👈\n' "$i"; else printf '1. #%s  \n' "$i"; fi
done
json=$(printf '"%s",' "${ids[@]}"); json="${json%,}"
printf '<!-- { "pr_train_prs": [%s] } -->\n</pr-train-toc>\n' "$json"
