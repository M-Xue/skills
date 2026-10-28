---
name: organise-changes-into-stacked-prs
description: >
  Split a large, already-implemented change (an uncommitted working tree, a WIP branch, or one
  giant commit) into a stack of small, independently reviewable pull requests (about 300 changed
  lines each, 500 max) made of atomic commits, then push them to GitHub with the `gh stack` CLI.
  Use this whenever the user asks to split, chunk, break up, carve up, or stack a change, PR,
  branch, or diff; says a PR is too big or hard to review; mentions stacked PRs, a PR train,
  `gh stack`, or atomic commits; or has just finished a big agent-implemented feature or bug fix
  and wants it organised for review. Trigger even when they only say "make this reviewable",
  "tidy these commits up before I open PRs", or "get this ready for review".
---

# Stacked PRs

## Why this skill exists

Agent-driven work tends to land as one large change: a whole feature or bug fix implemented in a
single pass. That is a good way to *build* software and a bad way to *review* it. A reviewer
handed 1,500 changed lines across 30 files has no path through the change, so the review either
drags on for days or gets rubber-stamped. Canva's own data shows PRs under about 300 changed
lines usually get reviewed within 24 hours and larger ones stretch over multiple days.

This skill runs at the **end** of implementation. The input is a finished change; the output is a
stack of PRs on GitHub where each PR is one atomic, mergeable step toward the feature, and each
commit inside a PR is one readable step toward that PR. Nothing from the original change is lost,
and the original is backed up before any history is rewritten.

Two levels of granularity:

- **PR** = one atomic unit of work that contributes to the end feature, mergeable on its own
  without breaking trunk wherever that is achievable. Target ~300 changed lines (additions +
  deletions), hard ceiling 500. Tests live in the same PR as the code they cover. Example: "add
  a retry helper to the shared http library", "extend the Foo proto and schema", "wire Foo into
  the editor behind a flag". When two pieces genuinely have to land together but are split
  anyway for readability, that is allowed; it just has to be called out (see "Co-dependent
  PRs" below).
- **Commit** = one step within a PR. A component change and its tests are separate commits. A
  mechanical rename or move is its own commit. Each commit should leave the tree buildable.

Read `references/splitting.md` for the full heuristics before planning. Read
`references/gh-stack.md` when you need exact command behaviour.

## Workflow

### 0. Preflight

```bash
gh extension list | grep -q gh-stack || gh extension install github/gh-stack
gh auth status
TRUNK=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)   # usually master at Canva
git status --short && git branch --show-current
```

Note the original branch name (call it `ORIG`), whether the tree is dirty, and the ticket id if
one is in the branch name or the conversation. Both "uncommitted working tree" and "branch with
commits" are fine starting states. If `ORIG` is trunk itself, pick a prefix for the new branches
from the ticket or feature name (e.g. `maxx/CA-1337`).

### 1. Build the safety net

Everything after this step rewrites history, so first make the original unlosable, then collapse
it to one commit on top of the latest trunk. Rebasing once here means merge conflicts surface in
one place, now, instead of inside every layer of the stack later.

```bash
git add -A && git commit -qm "wip: full change before stacking"      # only if the tree was dirty
git branch "backup/${ORIG}-$(date +%Y%m%d-%H%M)"                      # untouched copy; never delete it in this run
git fetch origin
git reset --soft "$(git merge-base HEAD origin/$TRUNK)" && git commit -qm "wip: full change"   # squash to one commit
git rebase "origin/$TRUNK"                                            # resolve conflicts here if any
git branch "${ORIG}-full"                                             # the rebased final state; all later checks compare against this
```

`${ORIG}-full` is the reference point for the rest of the run: the stack is correct when the top
branch's tree is identical to it.

### 2. Understand the change

Run `scripts/inventory.sh origin/$TRUNK` for a per-file table of added/deleted lines with totals,
subtotals per top-level directory, and flags for generated files, lockfiles and snapshots.

Then read the diff, not just the file list. For every file, work out:

- What it depends on and what depends on it (imports, call sites, schema consumers).
- Which kind of change it is: foundation (helpers, types, schema, protos), core logic, wiring and
  integration, tests, generated output, or mechanical (renames, moves, formatting).
- Whether its changes are one concern or several concerns that happen to share a file.

The quality of the split depends entirely on this understanding. A plan made from filenames alone
produces PRs that are the right size but tell no story.

### 3. Write the plan

Produce a plan table before touching git:

| # | Branch | Title | Goal (one sentence) | Files | Est. lines | Commits |
|---|--------|-------|---------------------|-------|-----------|---------|

Rules that matter most (details and examples in `references/splitting.md`):

- **Order bottom-up by dependency.** Foundation first, then core logic, then wiring, then the
  change that makes the feature reachable (flag flip, UI exposure, route registration). Each PR
  should leave trunk green and working if merged alone, even if the feature is not yet
  reachable. Temporarily unused code is fine; a broken build is not. If a split is worth making
  for review clarity even though the pieces cannot safely merge apart (a schema change and the
  only code that reads it, a rename across a package boundary and its call sites), mark those
  PRs as co-dependent in the plan so the user sees it before building.
- **Size.** Aim for 300 changed lines, never over 500. Generated files and lockfiles are counted
  but should not drive the split; call them out in the PR body instead. A single file that is
  over 500 lines by itself is split with the intermediate-state technique in step 4, or accepted
  with an explanation if it is genuinely indivisible.
- **Don't over-split.** A PR must mean something on its own. A 20-line PR that only makes sense
  alongside the next one belongs inside it. Most features land as 2 to 6 PRs.
- **Tests travel with their code**, in the same PR, as their own commit.
- **Commits are single steps**: refactor before behaviour change, mechanical changes alone,
  component change then its tests.
- **Branch names** carry the stack order: `${ORIG}-1-add-retry-helper`, `${ORIG}-2-foo-schema`,
  and so on. The number makes the stack readable in GitHub's branch list and in `gh stack view`.

Show the plan to the user and wait for a go-ahead unless they have already said to proceed without
checking. The plan is the cheapest place to fix a bad split; after step 4 a change costs a rebuild.

### 4. Build the stack

Start a new branch at trunk whose working tree holds the entire final change, unstaged:

```bash
git checkout -b "${PREFIX}-1-<slug>" "${ORIG}-full"
git reset --mixed "origin/$TRUNK"        # branch pointer at trunk; every change back in the working tree
gh stack init "${PREFIX}-1-<slug>"       # adopts the branch as the bottom layer
```

Now work through the plan, commit by commit. The working tree always holds "everything not yet
committed", so what remains shrinks to nothing by the end.

- **Whole files:** `git add -- <paths>` (this also stages deletions). Keep both halves of a
  rename in the same commit so git detects it as a rename.
- **Part of a file:** `git add -p` is interactive and hand-crafted patch files are error-prone,
  so instead edit the file in place down to its *intermediate state* (the final version minus
  the hunks that belong to later commits), `git add` it, commit, then restore the final version
  with `git checkout "${ORIG}-full" -- <path>`. You are good at editing files to a described
  state, and step 5 verifies against `${ORIG}-full` so any slip is caught.
- **Commit** with a message in the format from `references/splitting.md`: an imperative subject
  that completes "This commit ...", and a body that says why when the diff cannot.
- **At each PR boundary**, run the project's cheap checks on the tree as it stands (typecheck,
  lint, the tests touched so far). Every layer must stand on its own because a broken middle
  layer blocks everything above it, and reviewers approve layers independently. If the full
  suite is too expensive, run targeted tests and say in the PR body exactly what was run.
- Then `gh stack add "${PREFIX}-<n+1>-<slug>"`. This creates the next branch at HEAD and the
  uncommitted remainder carries over. `add` must be run from the top of the stack.

After the last commit, `git status --short` must print nothing and
`git diff "${ORIG}-full"` must be empty. If either shows something, a change was dropped or an
intermediate edit drifted. Put the fix in the layer it belongs to: `gh stack down` to that
branch, commit, then `gh stack rebase --no-trunk` to cascade, then `gh stack top`.

### 5. Verify

```bash
scripts/stack_sizes.sh                 # lines and commits per layer; warns over 300, fails over 500
git diff "${ORIG}-full" --stat         # must be empty from the top branch
gh stack view
git log --oneline "origin/$TRUNK"..HEAD   # should read like a story, bottom to top
```

Fix sizing or ordering problems now. Rebuilding a layer is cheap before anything is pushed.

### 6. Push and open PRs

Claude runs commands in a non-interactive terminal, so `gh stack submit` uses auto mode: it
pushes every branch, opens one **draft** PR per layer with a placeholder title, sets each PR's
base to the branch below, and links them into a stack on GitHub.

```bash
gh stack submit --auto
```

Then give every PR a real title and body with `gh pr edit <branch> --title ... --body-file ...`.
Start each body from `assets/pr-template.md` and fill it in following
`references/pr-description.md` (one of UX Solution or Bugged Behaviour, tick one Type of
Change, leave Before vs After blank). Once every PR exists and has its number, end each body
with the PR Train table of contents. The script reads the stack and its PR numbers itself and
prints the block with 👈 on the checked-out branch's PR; you do the swap:

```bash
gh stack bottom                                       # then gh stack up after each PR
scripts/generate_pr_train_toc.sh                      # prints the block for the current branch's PR
gh pr view --json body -q .body > body.md             # latest description of the current branch's PR
# edit body.md: delete any existing <pr-train-toc>...</pr-train-toc> block, append the printed block at the very end
gh pr edit --body-file body.md
```

Outside the stack's checkout, pass the PR ids bottom to top with `--current <pr>` instead.

Do this for every PR in the train; each one gets its own 👈. The block embeds the PR list in an
HTML comment so the train can be reconstructed from any one PR later. Always start from the
PR's current body on GitHub, not from the file you wrote earlier, so edits made in the browser
are kept.

**Every PR stays a draft, and no reviewers are ever assigned.** The user decides when a PR is
ready and who should look at it, after they have checked the split themselves. So: never pass
`--open` to `gh stack submit`, never run `gh pr ready`, and never use `--reviewer`,
`--add-reviewer`, `--assignee`, or request a review in any other way, even if a CODEOWNERS or
OWNERS file suggests who the reviewers would be. If the user asks you to do any of those, do it
then; do not do it by default.

If `submit` exits with code 9, stacked PRs are not enabled for the repository. Fall back to:

```bash
gh stack push
gh pr create --draft --head <branch> --base <branch-below or trunk> --title ... --body-file ...   # one per layer; always --draft, no --reviewer
```

then add the PR Train block to each body the same way as above.

### 7. Report

Finish with a table: PR number, title, base, changed lines, commits, URL. Name the backup branch
and `${ORIG}-full` so the user knows how to get back (`git checkout backup/...`). Leave both
branches in place; the user deletes them when the stack has merged. Remind the user that every
PR is a draft with no reviewers, and that they do both of those themselves.

Then, as the final part of the report, call out any **co-dependent PRs** (see below). If there
are none, say so in one line so the user knows you checked.

## Co-dependent PRs

The ideal is that every PR in the stack can merge on its own. Sometimes the split that reads best
in review is not the split that deploys safely: a proto change and the single handler that
consumes it, a config schema and the code that parses it, a rename across a package boundary and
its call sites. Splitting those for review is still the right call when it makes each diff
understandable, but the reader must not be left to discover the coupling by merging one half.

So whenever two or more PRs in the stack have to land together:

- Say so in the plan (step 3), so the user can push back before anything is built.
- Say so in each affected PR's Overview ("must merge together with #n; see the end of the
  report"), so a reviewer who approves one knows not to merge it alone.
- Say so explicitly at the end of the final report, in its own section, listing each group of
  PRs that must merge together and the one-sentence reason. `gh stack merge <top-pr-of-group>`
  merges a contiguous run of the stack atomically, so point the user at that as the way to land
  the group.

Do not quietly fold co-dependent pieces into one oversized PR to avoid the call-out. A 700-line
PR is worse for the reviewer than two 350-line PRs with a clear "these land together" note.

## After review feedback

- **Fix in one layer:** `gh stack checkout <pr-number>` (or `gh stack down`), commit the fix as a
  new commit so reviewers see only the delta, then `gh stack rebase --no-trunk` to cascade the
  change upward, then `gh stack push` (or `gh stack submit` if PR metadata needs updating).
- **Trunk moved:** `gh stack sync` fetches, rebases the whole stack, and force-pushes safely with
  `--force-with-lease`. On conflict it restores everything and tells you to run `gh stack rebase`.
- **Restructure the stack:** `gh stack modify` is interactive, so hand it to the user, or rebuild
  from `${ORIG}-full` with steps 4 and 5. Whenever a PR is added, removed, or reordered, regenerate
  the train block with `scripts/generate_pr_train_toc.sh` and swap it into every PR's body as in step 6.
  The old block's HTML comment tells you which PRs were in the train before.
- **Merge:** `gh stack merge` merges bottom-up atomically. Draft PRs cannot be merged.

## Reference files

- `references/splitting.md`: how to decide PR boundaries and commit boundaries, Canva's split
  axes, sizing rules, commit message format, a worked example.
- `references/gh-stack.md`: command reference for `gh stack`, exit codes, verified behaviours.
- `references/pr-description.md`: title conventions, how to fill each section of the PR body
  template, and the PR Train block.
- `assets/pr-template.md`: the PR body template to copy for every PR.
- `scripts/inventory.sh`: per-file change inventory against a base ref.
- `scripts/stack_sizes.sh`: changed lines and commit count per layer of the current stack.
- `scripts/generate_pr_train_toc.sh`: print the PR Train table-of-contents block for one PR of the
  train. Output only; swapping it into the description is done by hand with `gh pr view` and
  `gh pr edit`.
