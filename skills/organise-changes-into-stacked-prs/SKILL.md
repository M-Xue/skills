---
name: organise-changes-into-stacked-prs
description: >
  Split a large, already-implemented change (an uncommitted working tree, a WIP branch, or one
  giant commit) into a stack of small, independently reviewable pull requests (about 300 changed
  lines each, 500 max) made of atomic commits, push them as draft PRs with the `gh stack` CLI,
  and manage the stack afterwards (PR Train table of contents, rebasing, fixing a layer,
  restructuring). It does not write PR titles or descriptions; `submit-pr` is the entry point
  that decides whether to stack and then writes those. Use this directly whenever the user asks
  to split, chunk, break up, carve up, or stack a change, PR, branch, or diff; says a PR is too
  big; mentions stacked PRs, a PR train, `gh stack`, or atomic commits; or needs help operating
  an existing stack (sync, rebase, add a layer, regenerate the train block).
---

# Stacked PRs

## Why this skill exists

Agent-driven work tends to land as one large change: a whole feature or bug fix implemented in a
single pass. That is a good way to *build* software and a bad way to *review* it. A reviewer
handed 1,500 changed lines across 30 files has no path through the change, so the review either
drags on for days or gets rubber-stamped. In practice, PRs under about 300 changed lines
usually get reviewed within a day and larger ones stretch over multiple days.

This skill runs at the **end** of implementation. The input is a finished change; the output is a
stack of draft PRs on GitHub where each PR is one atomic, mergeable step toward the feature, and
each commit inside a PR is one readable step toward that PR. Nothing from the original change is
lost, and the original is backed up before any history is rewritten.

This skill is about the *shape* of the stack: where the boundaries go, how the branches and
commits are built, how `gh stack` is driven, and how the PR Train block is produced. It does not
write PR titles or descriptions. When it is invoked by `submit-pr`, that skill takes the report
from step 7 and writes a title and body for every layer; when it is invoked directly, tell the
user the PRs have placeholder titles and point them at `submit-pr`.

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
TRUNK=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
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

### 6. Push and open draft PRs

Claude runs commands in a non-interactive terminal, so `gh stack submit` uses auto mode: it
pushes every branch, opens one **draft** PR per layer with a placeholder title, sets each PR's
base to the branch below, and links them into a stack on GitHub.

```bash
gh stack submit --auto
```

Stop there. Do not write titles or bodies in this skill; that is `submit-pr`'s job, using the
report from step 7. The only body content this skill owns is the PR Train block below, and even
that is appended by `submit-pr` as the last step of composing each body.

**Every PR stays a draft, and no reviewers are ever assigned.** The user decides when a PR is
ready and who should look at it, after they have checked the split themselves. So: never pass
`--open` to `gh stack submit`, never run `gh pr ready`, and never use `--reviewer`,
`--add-reviewer`, `--assignee`, or request a review in any other way, even if a CODEOWNERS or
OWNERS file suggests who the reviewers would be. If the user asks you to do any of those, do it
then; do not do it by default.

If `submit` exits with code 9, stacked PRs are not enabled for the repository. Fall back to:

```bash
gh stack push
gh pr create --draft --head <branch> --base <branch-below or trunk> --title "<branch name>" --body ""   # one per layer; always --draft, no --reviewer
```

The placeholder title and empty body are replaced by `submit-pr`.

### 7. Report

The report is the handoff to `submit-pr`, so it must carry everything needed to write each
layer's title and description without re-deriving it. Produce:

1. A table with one row per layer, bottom to top: PR number, URL, branch, base branch, changed
   lines (and how many are generated), commit count, and the one-sentence goal from the plan.
2. For each layer, three short notes: what it **builds on** from lower layers, what it
   **introduces but leaves unused** until a higher layer (and which one), and exactly which
   **checks were run** on it in step 4.
3. The ticket, and whether the work as a whole is new behaviour or a bug fix.
4. Any **co-dependent PRs** (see below), as groups with a one-sentence reason each. If there
   are none, say so in one line so the reader knows you checked.
5. The backup branch and `${ORIG}-full`, so the user knows how to get back
   (`git checkout backup/...`). Leave both branches in place; the user deletes them when the
   stack has merged.

Remind the user that every PR is a draft with no reviewers and a placeholder title, and that
`submit-pr` is what writes the titles and descriptions.

## The PR Train block

Every PR in a stack ends with a PR Train table of contents, in this exact format:

```markdown
<pr-train-toc>

### 🚂 PR Train 
1. #1103425  
1. #1103427  👈
1. #1103428  
<!-- { "pr_train_prs": ["1103425","1103427","1103428"] } -->
</pr-train-toc>
```

Reviewers often open a PR from a notification without seeing GitHub's stack view. The train
shows them where this PR sits and what it builds on, which heads off the two most common
confusions: reviewing the cumulative diff against trunk, and asking for things that live in a
lower layer. The HTML comment carries the PR list, so the train can be reconstructed from any
one PR when the stack changes later.

`scripts/generate_pr_train_toc.sh` only prints the block. With no arguments it reads the current
`gh stack`, looks up each branch's PR number, and puts 👈 on the checked-out branch's PR. PR
numbers exist only after step 6, so the block is always produced after `gh stack submit`.

When `submit-pr` composes a body it appends this block as the final thing in the file. When the
stack changes later (a layer added, removed, or reordered) the block is swapped into every PR's
existing body by hand, once per branch of the stack:

```bash
gh stack bottom                                       # then gh stack up after each PR
scripts/generate_pr_train_toc.sh                      # prints the block for the current branch's PR
gh pr view --json body -q .body > body.md             # latest description of the current branch's PR
# edit body.md: delete any existing <pr-train-toc>...</pr-train-toc> block, append the printed block at the very end
gh pr edit --body-file body.md
```

Outside the stack's checkout, pass the PR ids bottom to top with `--current <pr>`:

```bash
scripts/generate_pr_train_toc.sh --current 1103427 1103425 1103427 1103428
```

Rules for the swap: exactly one block per description, always at the very end, never a stale
one left behind. Always start from the PR's current body on GitHub, not from the file you wrote
earlier, so edits made in the browser are kept.

## Co-dependent PRs

The ideal is that every PR in the stack can merge on its own. Sometimes the split that reads best
in review is not the split that deploys safely: a proto change and the single handler that
consumes it, a config schema and the code that parses it, a rename across a package boundary and
its call sites. Splitting those for review is still the right call when it makes each diff
understandable, but the reader must not be left to discover the coupling by merging one half.

So whenever two or more PRs in the stack have to land together:

- Say so in the plan (step 3), so the user can push back before anything is built.
- Say so in the report (step 7), in its own section, listing each group of PRs that must merge
  together and the one-sentence reason. `submit-pr` passes this to the description writer so
  each affected PR's Overview says "must merge together with #n", and a reviewer who approves
  one knows not to merge it alone.
- Point the user at `gh stack merge <top-pr-of-group>`, which merges a contiguous run of the
  stack atomically, as the way to land the group.

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
  the train block with `scripts/generate_pr_train_toc.sh` and swap it into every PR's body as
  described under "The PR Train block". The old block's HTML comment tells you which PRs were in
  the train before. A new layer needs a title and body too; hand that to `submit-pr`.
- **Merge:** `gh stack merge` merges bottom-up atomically. Draft PRs cannot be merged.

## Reference files

- `references/splitting.md`: how to decide PR boundaries and commit boundaries, the axes to
  split along, sizing rules, commit message format, a worked example.
- `references/gh-stack.md`: command reference for `gh stack`, exit codes, verified behaviours.
- `scripts/inventory.sh`: per-file change inventory against a base ref.
- `scripts/stack_sizes.sh`: changed lines and commit count per layer of the current stack.
- `scripts/generate_pr_train_toc.sh`: print the PR Train table-of-contents block for one PR of the
  train. Output only; swapping it into the description is done by hand with `gh pr view` and
  `gh pr edit`.

## Related skills

- `submit-pr`: the entry point. It decides whether a change needs a stack at all, invokes this
  skill when it does, and then writes a title and description for every layer and appends the
  PR Train block. This skill never calls `write-pr-description` itself.
