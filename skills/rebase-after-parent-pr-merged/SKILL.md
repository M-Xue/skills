---
name: rebase-after-parent-pr-merged
description: >
  Repairs a pull request whose branch was stacked on another branch that has since been merged
  into trunk, so the PR now shows the parent's old commits, a bloated diff, or conflicts. Asks
  the user for the two PRs (the merged parent and the child to repair), rebases only the child's
  own commits onto trunk with `git rebase --onto`, and force-pushes with a pinned
  `--force-with-lease` after the user confirms. Use this whenever the user says the branch their
  branch was based on, pointing at, or stacked on has been merged; that a PR "includes old
  commits from the parent branch"; asks to "rebase off master now the parent is merged", "fix
  the next PR in the train", or "restack"; or a PR in a stack went wrong after the one below it
  was squash-merged.
---

# Rebase after the parent PR was merged

## Why this happens

A child branch is cut from a parent branch, so its history is the parent's commits followed by
its own. When the parent PR is squash-merged, trunk gets one new commit with the same content
but a different hash. Git cannot tell that the parent's original commits are already in trunk,
so the child PR, now pointed at trunk, lists them again and often conflicts with the squashed
version of them.

The repair is to replay only the child's own commits onto trunk:

```
before:  trunk ── S (squashed parent)
              └── p1 ── p2 ── p3 ── c1 ── c2      child branch, p3 is the cut point

after:   trunk ── S ── c1' ── c2'
```

A plain `git rebase origin/<trunk>` is not enough, because it tries to replay `p1..p3` too.

## Workflow

### 1. Ask for the two PRs

Ask the user for both, in one question, before running anything else:

- **Parent PR:** the one that was merged.
- **Child PR:** the one to repair.

Accept a number or a URL for each. Do not infer either from the current branch, the
conversation, or `gh pr list`, even when a guess looks obvious; a stack often has several
candidates and the wrong pair rewrites the wrong branch. If the user already gave both in the
message that triggered this skill, restate them in one line and continue.

### 2. Preflight

```bash
gh pr view <parent> --json number,state,mergedAt,headRefName,headRefOid,baseRefName
gh pr view <child>  --json number,state,headRefName,headRefOid,baseRefName,commits
TRUNK=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
git fetch origin "$TRUNK" "<child-branch>"
git fetch origin "pull/<parent>/head"     # the parent branch is usually deleted; this still works
git status --short && git branch --show-current
```

Stop and tell the user, without changing anything, when:

- The parent PR is not `MERGED`. There is nothing to repair yet.
- The parent was merged into something other than trunk. Ask what the child should sit on.
- The working tree is dirty. Ask the user to commit or discard; never use a bare `git stash`
  (in a worktree the stash stack is shared).
- `origin/<child-branch>` has commits the local branch lacks. Someone else pushed; ask.

Check out the child branch if it is not the current one. Record two hashes for later:
`OLD_LOCAL=$(git rev-parse HEAD)` and `OLD_REMOTE=$(git rev-parse origin/<child-branch>)`.

### 3. Find the cut point

The cut point is the last commit in the child's history that belongs to the parent.

```bash
PARENT_HEAD=<headRefOid of the parent PR>
git merge-base --is-ancestor "$PARENT_HEAD" HEAD && CUT=$PARENT_HEAD || CUT=$(git merge-base "$PARENT_HEAD" HEAD)
git log --oneline "$CUT"..HEAD
```

The second form covers a parent that gained commits after the child was cut. The log is the
list of commits that will be replayed. Every one of them must be the child's own work. Show
the list to the user and ask before continuing if any of these is true:

- A listed commit looks like the parent's (same subject as a parent PR commit, or files only
  the parent touched).
- The list contains merge commits.
- `CUT` is already an ancestor of `origin/$TRUNK`, which means the child never contained the
  parent's commits and a normal rebase is all it needs.

### 4. Rebase

```bash
git rebase --onto "origin/$TRUNK" "$CUT" "<child-branch>"
```

On conflicts:

- Resolve each one by keeping the intent of both sides: the child's change, applied to trunk's
  current version of the file.
- Generated files (`BUILD.bazel`, `tsconfig.json`, lockfiles, snapshots): keep both sides'
  entries to get through the rebase, then regenerate with the repository's tool afterwards if
  it has one, and check the result matches.
- Touch only the conflicted hunks. If a non-conflicting line also has to change for the code to
  be consistent, make the change and name it in the report.
- Never bring back code the child branch deliberately deleted because trunk still has it.
- If a conflict is a real design decision (both sides rewrote the same logic differently), stop
  at the conflict, leave the rebase in progress, and ask the user.

Do not run tests. Formatting, generation and lint are fine.

### 5. Verify before pushing

```bash
git log --oneline "origin/$TRUNK"..HEAD            # only the child's commits, same count as step 3
git range-diff "$CUT".."$OLD_LOCAL" "origin/$TRUNK"..HEAD
git diff --stat "origin/$TRUNK"...HEAD
```

`range-diff` pairs each old commit with its replayed version; anything other than conflict
resolutions showing up as a difference needs explaining. The diff stat should contain only
files the child PR is meant to change.

### 6. Confirm, then push

The rebase is local and reversible; the push rewrites the PR. Show the user:

- the commits now on the branch and the file count,
- every conflict and how it was resolved,
- the exact push command,

and ask for a go-ahead. This confirmation is required every time, including when the user has a
standing rule against pushing: invoking this skill is the request to repair the PR, and the
confirmation is the explicit approval of this push. If they decline, leave the rebased branch
in place and give them the command.

```bash
git push --force-with-lease="<child-branch>:$OLD_REMOTE" origin "<child-branch>"
```

Always use the pinned form. It rejects the push if the remote branch is no longer at
`$OLD_REMOTE`, so it cannot overwrite a commit someone pushed in the meantime. Never use
`--force`, and never the bare `--force-with-lease`, which fails on a branch with no upstream
and protects less after a fetch.

If the child PR's base is still the parent branch, retarget it as part of the same
confirmation: `gh pr edit <child> --base "$TRUNK"`. Do not change the PR's title or body.

### 7. Check the PR and report

```bash
gh pr view <child> --json commits,changedFiles,mergeable,baseRefName
```

Report in a few lines: commits and files before and after, whether the PR is mergeable, the
conflicts resolved, anything changed outside a conflict, and how to undo
(`git reset --hard $OLD_LOCAL`, then push with a lease on the new remote hash). Say which checks
were run and which were not.

If the child PR has its own child, say so: that one now has the same problem, and this skill
runs again with the PR just repaired as the parent once it merges.
