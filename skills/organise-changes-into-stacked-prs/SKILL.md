---
name: organise-changes-into-stacked-prs
description: >
  Split a large, already-implemented change (an uncommitted working tree, a WIP branch, or one
  giant commit) into a `gh stack` of small, independently reviewable branches made of atomic
  commits, one branch per future pull request. Use whenever the user asks to split, chunk,
  break up, or stack a change, PR, branch, or diff; says a PR is too big; mentions stacked PRs,
  `gh stack`, or atomic commits; or needs help operating an existing stack (rebase onto trunk, fix a
  layer, add a layer).
---

# Stacked PRs

A reviewer handed 1,500 changed lines across 30 files has no path through the change. This skill
runs at the **end** of implementation: it takes a finished change and produces a local `gh stack`
of branches where each branch is one mergeable step toward the feature and each commit is one
readable step toward that branch. Nothing from the original is lost.

The output is the stack itself: branches and commits, verified against the original. Pushing,
opening pull requests, and writing their titles and descriptions are out of scope.

Read `references/splitting-heuristics.md` before planning. It defines what an atomic PR and an
atomic commit are, how to order and size layers, and how to split a single file across layers.

## Workflow

### 0. Preflight

```bash
gh extension list | grep -q gh-stack || gh extension install github/gh-stack
gh auth status
TRUNK=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
git status --short && git branch --show-current
```

Note the original branch (`ORIG`), whether the tree is dirty, and the ticket id if one is in the
branch name or conversation. If `ORIG` is trunk itself, pick a prefix for the new branches from
the ticket or feature (e.g. `CA-1337`); otherwise `PREFIX` is `ORIG`. Never use `/` in a branch
name.
If the stack should target a branch other than the default (a release branch, say), set `TRUNK`
to it and pass `--base "$TRUNK"` to `gh stack init` in step 4.

### 1. Build the reference branch

`ORIG` is never rewritten; it is the backup. All work happens on a copy squashed to one commit on
top of the latest trunk, so merge conflicts surface once, here, instead of inside every layer.

```bash
git add -A && git commit -qm "wip: full change before stacking"   # only if the tree was dirty
git fetch origin
git checkout -b "${ORIG}-full"
git reset --soft "$(git merge-base HEAD origin/$TRUNK)" && git commit -qm "wip: full change"
git rebase "origin/$TRUNK"                                        # resolve conflicts here if any
```

`${ORIG}-full` is the reference point for the rest of the run: the stack is correct when the top
branch's tree is identical to it.

### 2. Understand the change

Start with the numbers:

```bash
git diff --numstat "origin/$TRUNK" | sort -nr    # added, deleted, path; largest first
git diff --stat "origin/$TRUNK" | tail -1        # total files and lines
```

Note which files are generated output, lockfiles or snapshots. They count toward a layer's size
but add no review load, so they should not drive the split.

Then read the diff, not just the file list. For every file, work out what it depends on and what
depends on it, which kind of change it is (foundation, core logic, wiring, tests, generated,
mechanical), and whether it holds one concern or several. A plan made from filenames alone
produces PRs that are the right size but tell no story.

### 3. Write the plan

If the whole change is under about 400 lines and one concern, it does not need a stack. Say so
and stop. Otherwise produce this table before touching git, applying the rules in
`references/splitting-heuristics.md`:

| #   | Branch | Goal (one sentence) | Files | Est. lines | Commits |
| --- | ------ | ------------------- | ----- | ---------- | ------- |

Branch names carry the stack order: `${PREFIX}-1-add-retry-helper`, `${PREFIX}-2-foo-schema`.
If two layers cannot safely merge apart but are split anyway for readability, mark them as
co-dependent in the plan. Show the plan to the user and wait for a go-ahead unless they have
already said to proceed without checking; after step 4 a change costs a rebuild.

### 4. Build the stack

Start the bottom branch at trunk with the entire final change unstaged in the working tree:

```bash
git checkout -b "${PREFIX}-1-<slug>" "${ORIG}-full"
git reset --mixed "origin/$TRUNK"        # pointer at trunk; every change back in the working tree
gh stack init "${PREFIX}-1-<slug>"       # adopts the branch as the bottom layer
```

Work through the plan commit by commit. The working tree always holds "everything not yet
committed", so what remains shrinks to nothing by the end.

- **Whole files:** `git add -- <paths>` (this also stages deletions). Keep both halves of a
  rename in the same commit so git detects it.
- **Part of a file:** edit the file in place down to its _intermediate state_ (the final version
  minus the hunks that belong to later commits), `git add` it, commit, then restore the final
  version with `git checkout "${ORIG}-full" -- <path>`. Do not use `git add -p` or hand-written
  patch files.
- **Commit** with an imperative subject that completes "This commit ...", and a body that says
  why when the diff cannot (format in `references/splitting-heuristics.md`).
- **At each PR boundary**, run the project's cheap checks on the tree as it stands (typecheck,
  lint, the tests touched so far). A broken middle layer blocks everything above it. Note what
  was run for the report.
- Then `gh stack add "${PREFIX}-<n+1>-<slug>"` from the top of the stack. It creates the next
  branch at HEAD and the uncommitted remainder carries over.

After the last commit, `git status --short` must print nothing and `git diff "${ORIG}-full"` must
be empty. If not, a change was dropped or an intermediate edit drifted. Fix it in the layer it
belongs to: `gh stack down` to that branch, commit, `gh stack rebase --no-trunk` to cascade,
then `gh stack top`. `rebase` refuses to run with a dirty working tree and never stashes for
you, so everything must be committed before the cascade.

### 5. Verify

```bash
prev="origin/$TRUNK"                      # lines and commits per layer
for b in $(gh stack view --json | jq -r '.branches[].name'); do
  printf '%-40s %s  (%s commits)\n' "$b" "$(git diff --shortstat "$prev" "$b")" "$(git rev-list --count "$prev..$b")"
  prev="$b"
done
git diff "${ORIG}-full" --stat            # must be empty from the top branch
gh stack view
git log --oneline "origin/$TRUNK"..HEAD   # should read like a story, bottom to top
```

Insertions plus deletions is the layer's size: over 300 is a prompt to look for a seam, over 500
is a defect in the plan. Fix sizing or ordering problems now; rebuilding a layer is cheap while
the stack is local.

### 6. Report

1. A table, bottom to top: branch, base branch, changed lines (and how many are generated),
   commit count, one-sentence goal.
2. Checks run per layer in step 4.
3. Co-dependent groups, each with a one-sentence reason, and the instruction to land a group with
   `gh stack merge <top-of-group>`, which merges a contiguous run atomically. If there are none,
   say so in one line.
4. Where the original is: `ORIG` (untouched) and `${ORIG}-full` (rebased). Leave both in place;
   the user deletes them when the stack has merged.

State that the stack is local and nothing has been pushed.

## After review feedback

- **Fix one layer:** `gh stack checkout <branch>` (or `gh stack down`), commit the fix as a new
  commit so reviewers see only the delta, then `gh stack rebase --no-trunk` to cascade it upward.
- **Trunk moved:** `gh stack rebase` fetches trunk and cascades the whole stack. On conflict, fix
  the files, `git add`, then `gh stack rebase --continue`; `--abort` restores every branch.
- **Restructure:** `gh stack modify` is interactive, so hand it to the user, or rebuild from
  `${ORIG}-full` with steps 4 and 5.

## gh stack reference

Install: `gh extension install github/gh-stack` (needs `gh` 2.90+, git 2.36+). Docs at
https://gh.io/stacks; `gh stack <cmd> --help` is authoritative. A stack is an ordered list of
branches, bottom on trunk, each based on the one below.

Two behaviours this skill relies on are observed, not documented: `init` and `add` accept a dirty
working tree and carry it over to the new branch, and `view --json` returns `branches[].name`
ordered bottom to top. If either stops holding, steps 4 and 5 need revisiting.

| Command | What it does |
|---|---|
| `gh stack init <branch> [--base <trunk>]` | Start a stack; adopts the branch if it exists, creates it otherwise. Turns on `git rerere`. |
| `gh stack add <branch>` | Create a branch at HEAD on top of the stack and check it out. Run from the top. |
| `gh stack view [--json]` | Branches, order, status. `--json` for scripts. |
| `gh stack up/down [n]`, `top`, `bottom` | Navigate. Bottom is nearest trunk. |
| `gh stack checkout <branch>` | Check out a stack by branch, pulling it from GitHub if it is not tracked locally. |
| `gh stack rebase [--no-trunk] [--continue\|--abort]` | Cascading rebase. Fetches and rebases onto trunk first unless `--no-trunk`. Needs a clean tree. |
| `gh stack modify` | Interactive restructuring (drop, fold, insert, reorder, rename). Hand to the user. |

Exit codes you can hit from these commands: 2 not in a stack, 3 rebase conflict, 7 rebase already
in progress, 8 stack locked by another process, 10 interrupted modify session needing
`gh stack modify --continue` or `--abort`.

## Files

- `references/splitting-heuristics.md`: PR and commit boundaries, ordering, sizing, single-file
  splits, commit message format, a worked example.
