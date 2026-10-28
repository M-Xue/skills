# gh stack command reference

`gh stack` is GitHub's official CLI extension for stacked pull requests. Install with
`gh extension install github/gh-stack`. Requires `gh` 2.90+ and git 2.36+. Full docs:
https://gh.io/stacks. Run `gh stack <cmd> --help` for the authoritative text.

## Mental model

- A stack is an ordered list of branches. The bottom branch is based on trunk; each branch above
  is based on the one below. Each PR's diff is just its own layer.
- Stack tracking is stored locally in the repo (and on GitHub once submitted). Only the branches
  in the stack are pushed; other branches like `backup/...` and `<orig>-full` stay local.
- Commands are serialized per clone and work across worktrees.

## Behaviours verified in a test repo

- `gh stack init <branch>` and `gh stack add <branch>` both succeed with a dirty working tree.
  The uncommitted changes carry over to the new branch, which is what lets you build the stack
  incrementally while the remaining diff rides along.
- `gh stack init` adopts an existing branch if it already exists, and creates it if not.
- `gh stack view --json` returns `{"trunk": "...", "currentBranch": "...", "branches": [{"name",
  "base", "isCurrent", "isMerged", "isQueued", "needsRebase"}, ...]}` ordered bottom to top.
- `gh stack init` turns on `git rerere` so repeated conflict resolutions are replayed.

## Stack management

| Command | What it does |
|---|---|
| `gh stack init [branches...] [--base <trunk>]` | Start a stack. With names, adopts existing branches and creates missing ones, bottom to top. Defaults the trunk to the repo's default branch. |
| `gh stack add <branch> [-m msg] [-A\|-u]` | Create a branch at HEAD on top of the stack and check it out. Must be run from the top branch. `-m` commits first; `-A` stages everything including untracked, `-u` stages tracked only. |
| `gh stack view [--short] [--json]` | Show branches, order, PR links and status. `--json` for scripts. |
| `gh stack checkout <stack#\|pr#\|pr-url\|branch>` | Check out a stack, pulling it down from GitHub if needed. |
| `gh stack modify` | Interactive restructuring (drop, fold, move, rename). Needs a clean tree. Hand this to the user; it cannot be driven non-interactively. |
| `gh stack unstack [--local]` | Remove the stack from GitHub and local tracking (or local only). Branches and PRs survive. |

## Remote operations

| Command | What it does |
|---|---|
| `gh stack submit [--auto] [--open]` | Push all branches, create PRs for branches without one, set each PR's base to the branch below, and link them as a stack on GitHub. In a non-interactive terminal (which is what Claude has) it behaves as `--auto`: generated titles, PRs created as **drafts**. `--open` makes them ready for review. |
| `gh stack push` | Push active branches with per-branch `--force-with-lease`. Does not touch PRs. Not atomic across branches. |
| `gh stack sync [--prune]` | Fetch, reconcile with the remote stack, fast-forward trunk, cascade-rebase, push atomically with `--force-with-lease --atomic`, refresh PR state. Never opens PRs. On a rebase conflict it restores all branches and tells you to run `gh stack rebase`. `--prune` deletes local branches whose PRs merged. |
| `gh stack rebase [--no-trunk] [--downstack] [--upstack] [--continue] [--abort]` | Cascading rebase. `--no-trunk` only rebases layers onto each other (use after amending a middle layer). On conflict: fix files, `git add`, then `--continue`; `--abort` restores everything. |
| `gh stack link <args...>` | Link existing branches or PRs into a GitHub stack without local tracking. For other tools. |
| `gh stack merge [<stack#>\|<pr#>] [--squash\|--merge\|--rebase] [-y]` | Atomic all-or-nothing merge of the stack up to a chosen PR. PRs must be open and not drafts. Respects branch protection; cannot bypass. With a merge queue, enqueues instead. |

## Navigation

`gh stack up [n]`, `gh stack down [n]`, `gh stack top`, `gh stack bottom`, `gh stack trunk`,
`gh stack switch` (interactive). Bottom is nearest trunk. Merged branches are skipped. All
accept `--print-path` to print the worktree path instead of switching.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Generic error |
| 2 | Not in a stack, or stack not found |
| 3 | Rebase conflict |
| 4 | GitHub API failure |
| 5 | Invalid arguments or flags |
| 6 | Disambiguation required (branch in multiple stacks) |
| 7 | Rebase already in progress |
| 8 | Stack locked by another process |
| 9 | Stacked PRs not enabled for this repository (fall back to `gh stack push` + `gh pr create --base <parent>`) |
| 10 | Modify session interrupted; recovery required |

## Setting PR titles and bodies non-interactively

`submit --auto` cannot take titles, so set them afterwards per branch:

```bash
gh pr edit <branch> --title "<title>" --body-file <path>
gh pr ready <branch>          # when the user wants it out of draft
```

`gh pr view <branch> --json number,url` gives the number and URL for the final report.
