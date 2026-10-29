---
name: submit-pr
description: >
  Entry point for getting a finished change onto GitHub for review. Measures the change, decides
  with explicit heuristics whether it should be one pull request or a stack of stacked PRs
  (over the 300-to-500 changed-line limit, or containing work that reasonably splits), then
  pushes, opens the PRs as drafts, writes a title and description for each, and adds the PR
  Train table of contents to every PR in a stack. Use this whenever the user asks to submit,
  open, create, raise, or push up a PR; says "make this reviewable", "get this ready for
  review", "ship this for review", or "PR this"; or has just finished implementing something and
  wants it in front of reviewers. Everything it opens stays a draft with no reviewers.
---

# Submit a PR

## What this skill does

A finished change goes through three questions on its way to review: should it be one PR or
several, what does each PR say, and how is that applied on GitHub? This skill answers the first
question itself, delegates the structural work and the prose to two other skills, and does
everything that touches GitHub:

| Concern                                                                                                          | Owner                               |
| ---------------------------------------------------------------------------------------------------------------- | ----------------------------------- |
| Should this be a stack? (heuristics below)                                                                       | this skill                          |
| Splitting the change into a local `gh stack` of branches with atomic commits                                     | `organise-changes-into-stacked-prs` |
| The body of each PR, from its diff and the context passed in                                                     | `write-pr-description`              |
| Pushing, opening draft PRs, titles, per-layer chained context, the PR Train block, `gh pr create` / `gh pr edit` | this skill                          |

Read `write-pr-description/SKILL.md` and the step 6 report format in
`organise-changes-into-stacked-prs/SKILL.md` before starting, so you know what each one expects
and returns. Both skills live beside this one; paths below are relative to the skills directory.

## Workflow

### 0. Preflight

```bash
gh auth status
TRUNK=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
git fetch origin
git status --short && git branch --show-current
git log --oneline "origin/$TRUNK"..HEAD
```

Note the branch, whether the tree is dirty, whether a PR already exists for the branch
(`gh pr view --json number,url,isDraft,body` succeeds), and the ticket id if one is in the branch
name or the conversation.

### 1. Measure the change

Measure against trunk, including uncommitted and untracked work:

```bash
git add -A -N                                        # make untracked files visible to diff
git diff --numstat "origin/$TRUNK" | sort -nr        # added, deleted, path; largest first
git diff --shortstat "origin/$TRUNK"                 # total files and lines
```

Insertions plus deletions is the "changed lines" figure used below. Note which files are
generated output, lockfiles, snapshots, or pure moves and renames; those lines are excluded from
"meaningful lines" in the heuristics.

Then skim the diff itself, because the decision in step 2 turns on what the change _is_, not
only how big it is. Note how many distinct concerns it contains, whether there is a
foundation-then-consumer shape, how many directories or ownership areas it touches, and what
share of the lines is generated or mechanical.

### 2. Decide: one PR or a stack

Apply the heuristics in the next section and write the verdict down in one or two sentences
("1,240 changed lines across three concerns: new schema, parser, and UI wiring. Stack."). Then:

- **Clearly one PR** (under 300 meaningful lines, one concern): go to step 3.
- **Clearly a stack** (over 500 meaningful lines, or two or more concerns that can each be
  reviewed on their own): go to step 4.
- **Borderline** (300 to 500 lines with a weak seam, or one concern that is large only because
  of generated output): state your recommendation and the reason, and ask the user unless they
  already said to proceed without checking. Default to one PR when the seam would produce a
  layer that means nothing alone.

### 3. Single PR path

1. Tidy the branch only as far as needed: commit a dirty tree with a real message; do not
   rewrite history the user did not ask you to rewrite.
2. Push: `git push -u origin HEAD`.
3. Get the body: invoke `write-pr-description` with the diff `git diff origin/$TRUNK...HEAD`
   and the ticket. Have it write the body to a temp file.
4. Compose the title (see "Titles").
5. Open or update the PR, always as a draft and never with reviewers:

```bash
gh pr create --draft --title "<title>" --body-file body.md            # new PR
gh pr edit <number> --title "<title>" --body-file body.md             # existing PR
```

No PR Train block on a single PR.

### 4. Stack path

1. **Build the stack.** Invoke `organise-changes-into-stacked-prs`. It plans the split, shows
   the plan to the user, builds and verifies a local `gh stack`, and returns its step 6 report:
   one row per layer (branch, base, lines and how many are generated, commits, goal), the checks
   run per layer, any co-dependent groups, and the names of the untouched original branch and
   the rebased `<orig>-full` branch. Nothing is pushed at this point.

2. **Push and open draft PRs.** From the top branch of the stack:

   ```bash
   gh stack submit --auto
   ```

   In a non-interactive terminal this pushes every branch, opens one draft PR per layer with a
   generated title and empty body, sets each base to the branch below, and links them as a stack
   on GitHub. Never pass `--open`. If it exits with code 9, stacked PRs are not enabled for the
   repository; fall back to `gh stack push` and then, per layer bottom to top,
   `gh pr create --draft --head <branch> --base <branch-below or trunk> --title "<branch>" --body ""`.

3. **Collect the PR numbers**, bottom to top, and keep the list; the train block needs it:

   ```bash
   for b in $(gh stack view --json | jq -r '.branches[].name'); do
     printf '%s %s\n' "$b" "$(gh pr view "$b" --json number,url -q '"\(.number) \(.url)"')"
   done
   ```

4. **Write each layer.** Walk the stack bottom to top. For each layer:
   1. Build the **chained context** (see below) from the stack report, the layer's diff, and
      the layers already written.
   2. Get the layer's own diff: `git diff <base-branch>...<branch>`, never the cumulative diff
      against trunk.
   3. Invoke `write-pr-description` with that diff, the ticket,
      and the chained context. Have it write the body to a temp file.
   4. Compose the title (see "Titles").
   5. Append the PR Train block for this layer (see "The PR Train block") as the very last
      thing in the body file, after one blank line. One block per body, only at the end.
   6. Apply: `gh pr edit <number> --title "<title>" --body-file body.md`.
5. **Check.** After the last layer, confirm with `gh stack view` and one
   `gh pr view <number> --json title,body` per PR that every PR has a real title, a filled body,
   and exactly one train block whose 👈 points at itself.

### 5. Report

A table: PR number, title, base, changed lines, commits, URL, in stack order. State the verdict
from step 2 and why. Repeat any co-dependent groups from the stack report, with the
`gh stack merge <top-pr-of-group>` hint. Name the original and `<orig>-full` branches the stack
skill left behind, so the user knows how to get back and what to delete once the stack merges.
Remind the user that every PR is a draft with no reviewers and that they take both of those
steps themselves.

## Heuristics: should this be a stack?

Size is the trigger most people know, but it is a proxy. The real question is whether a reviewer
can hold the whole change in their head and approve it in one sitting. Work through these in
order; the first firm answer wins, and "meaningful lines" means changed lines excluding
generated files, lockfiles, snapshots, and pure moves or renames.

**Split when any of these holds:**

1. **Over 500 meaningful lines.** Always split. 500 is the ceiling for one PR, not a target.
2. **Over 300 meaningful lines and there is a seam.** A seam is a boundary where the part below
   builds and makes sense without the part above: a helper and its first caller, a schema and
   its consumer, a refactor and the behaviour change it enables. Over 300 with a seam is a
   stack; over 300 with no seam is one PR with a note in Technical Solution saying why.
3. **Two or more independent concerns, at any size.** Two unrelated bug fixes, a drive-by
   refactor plus the feature, a dependency bump plus the code that needed it. Each concern can
   be approved or reverted alone, so each gets its own PR, even if together they are only 200
   lines.
4. **A refactor or mechanical change mixed with a behaviour change.** Renames, moves,
   formatting, extract-method, and generated regeneration are near-zero risk and reviewed by
   skimming; the behaviour change is reviewed line by line. Mixing them makes the reviewer do
   the slow kind of reading on the fast kind of diff. Split them, mechanical first.
5. **Foundation that other teams could use or that a different owner reviews.** New shared
   helpers, types, protos, or config schema touching a different ownership area (CODEOWNERS,
   different top-level directory) than the feature code. The foundation PR can go to its owner
   while the feature PR goes to yours.
6. **Different risk profiles.** A safe, unreachable preparation step (code behind a flag, a new
   unused table) and the step that makes it live (flag flip, route registration, migration run).
   Reviewers want to scrutinise the second much harder than the first, and want to be able to
   revert it alone.
7. **Tests or fixtures that dwarf the code.** Large recorded fixtures, golden files, or test
   data additions that push an otherwise small change over the limits. Keep each test with the
   code it covers, but a fixture-heavy layer can be its own PR when the code it exercises is a
   clean layer below.

**Do not split when:**

- Under about 300 meaningful lines and one concern, even if it touches many files. A broad
  rename or a one-concept change across a package is still one review.
- The only possible seam produces a layer that means nothing on its own (a 20-line PR that
  exists to make the next one smaller). Fold it in.
- The size comes from a single indivisible generated artefact or lockfile. Keep it in one PR
  and say in the body how many lines are generated.
- The pieces cannot be reviewed independently _and_ cannot be merged independently _and_ the
  split would not make either diff easier to read. Two halves of one tangled change are worse
  than one honest 400-line PR. (Two halves that _are_ easier to read but must merge together are
  still split, and marked co-dependent; see the stack skill.)

When the heuristics point both ways, prefer the split that produces the clearest story for the
reviewer, not the one that produces the smallest numbers.

## Chained context

Each layer's description must read correctly to a reviewer who opens only that PR, and must not
repeat what the layers below already said. The stack report gives you each layer's goal, size,
checks, and co-dependencies; the rest you derive from the layer's diff and the layers already
written. Pass it to `write-pr-description` verbatim:

- **Position:** "Layer n of m in a stack for <ticket or feature>." No counter in the title; the
  train block shows this.
- **Builds on:** the PR numbers and one-line goals of the layers below that this layer directly
  uses (look at what the diff imports or calls that a lower layer introduced), so the Overview
  can say "uses the retry helper from #101" instead of re-explaining it.
- **Leaves unused:** what this layer introduces that nothing calls yet, and the PR number where
  it becomes used (look ahead at the higher layers' diffs), so the reviewer does not ask for the
  caller.
- **Co-dependent with:** the PR numbers this layer must merge together with and why, if the
  stack report lists it in a group. Otherwise say "none" explicitly.
- **Checks run on this layer:** exactly as the stack report records them, so Technical
  Solution is truthful about what was and was not run.
- **Which behaviour section the stack uses:** UX Solution for new behaviour, Bugged Behaviour
  for a fix, decided once for the whole stack and applied to every layer. For layers with no
  user-visible effect, name the layer where the behaviour becomes visible so the writer can
  point to it.
- **Generated lines in this layer**, from the stack report's count.

Carry the written layers forward: once layer 1's body is written, its one-line summary becomes
part of the "builds on" context for layer 2, and so on. This is what keeps the descriptions
consistent across the stack.

## Titles

The title completes the sentence "This change ...", names the affected package or component,
and includes the ticket when there is one. Common formats:

- `[TICKET-123] <description>`
- `<package>: <description> [TICKET-123]`

Good:

- `[PUB-212] Add ScheduledPublish proto and regenerated bindings`
- `publish/server: add SchedulerStore with DynamoDB implementation [PUB-212]`

Bad: `wip`, `part 2`, `update proto`, `more changes`. A reviewer scanning their queue should
know what the PR does from the title alone.

Rules:

- Use the ticket format the repository already uses (look at recent merged PRs with
  `gh pr list --state merged --limit 20`), and the same ticket on every layer of a stack.
- No "(1/5)" style counters. Stack order changes when layers are folded or inserted, and the PR
  Train block already shows position.
- Each layer's title describes that layer, not the feature. "Add retry helper to http client"
  rather than "Scheduled publishing".
- Keep it under about 70 characters so it is not truncated in lists.

## The PR Train block

Every PR in a stack ends with a table of contents for the stack, in this exact format:

```markdown
<pr-train-toc>

### 🚂 PR Train

1. #1103425
1. #1103427 👈
1. #1103428

<!-- { "pr_train_prs": ["1103425","1103427","1103428"] } -->
</pr-train-toc>
```

- One `1. #<number>` line per PR in the stack, bottom to top, using the numbers collected in
  step 4.3. Every line is numbered `1.` so markdown renumbers them.
- 👈 at the end of the line for the PR whose body this is, and nowhere else.
- The HTML comment carries the same numbers, as strings, in the same order. It is what lets the
  train be rebuilt from any one PR when the stack changes later.

Reviewers often open a PR from a notification without seeing GitHub's stack view. The train
shows them where this PR sits and what it builds on, which heads off the two most common
confusions: reviewing the cumulative diff against trunk, and asking for things that live in a
lower layer.

Rules: exactly one block per body, always the very last thing in it, never a stale one left
behind. When refreshing an existing PR, start from the live body on GitHub, strip any existing
`<pr-train-toc>...</pr-train-toc>` block, and append a fresh one.

## Composing and applying the body

The final body is always:

```
<body from write-pr-description>

<PR Train block, stack PRs only>
```

- `write-pr-description` returns the body without a title and without any train block. Do not
  edit its prose except to fix a fact it got wrong from the context you gave it.
- When updating a PR that already has a body, fetch the live one first
  (`gh pr view <number> --json body -q .body`), pass it to `write-pr-description` as the
  existing body, delete any existing `<pr-train-toc>...</pr-train-toc>` block from the result,
  then append a fresh one. Never leave two blocks or a stale one.
- Apply title and body in one call: `gh pr edit <number> --title "<title>" --body-file body.md`.

## Draft and reviewers

Every PR this skill opens or edits stays a **draft** with **no reviewers and no assignees**.
Never pass `--reviewer`, `--assignee`, or `--open`, never run `gh pr ready`, and never request a
review by any other route, even when CODEOWNERS makes the reviewer obvious. The user checks the
split and the descriptions, then marks ready and picks reviewers themselves. If the user asks you
to do either of those, do it then; do not do it by default.

## Re-running

If PRs already exist (a re-submit after review feedback or a restructured stack):

- Single PR: push, re-measure, and if it has grown past the heuristics say so and offer to
  stack it. Otherwise refresh the body via the update path above.
- Stack: let `organise-changes-into-stacked-prs` do the rebase or restructure (its "After review
  feedback" section), then push with `gh stack submit --auto` (which also opens PRs for any new
  layers and fixes bases) or `gh stack push` (branches only). Rewrite titles and bodies only for
  layers whose diff or position changed. If the set of PRs changed, re-collect the numbers and
  swap a fresh train block into every layer's body, including the unchanged ones.

## Related skills

- `organise-changes-into-stacked-prs`: builds and verifies a local stack of branches. Invoked
  from step 4; it never pushes, opens PRs, or writes titles or bodies.
- `write-pr-description`: the body of one PR from its diff and the context passed in. Invoked
  from steps 3 and 4; it never sets titles or touches GitHub.
