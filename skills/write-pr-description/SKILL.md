---
name: write-pr-description
description: >
  Write the title and description for a GitHub pull request using Canva's PR body template
  (Overview, Related Issue, Type of Change, UX Solution or Bugged Behaviour, Technical Solution,
  Before vs After), then apply it with `gh pr edit`. Use this whenever the user asks to write,
  fill in, draft, update, or improve a PR description, PR body, or PR title; asks to "describe
  this PR" or "fill in the PR template"; or whenever another skill or workflow has just opened a
  PR that still has a placeholder title or empty body. Works for a single PR and for each layer
  of a stack.
---

# Write a PR description

A PR description is the reviewer's way into the diff. The title tells them whether to open it
now; the body tells them what changed, why, and what was checked, so they can review the change
instead of reverse-engineering it. This skill produces both from the diff and whatever context
the conversation holds (ticket, design notes, what was tested), and applies them with `gh`.

## Inputs

Before writing, know:

- **The diff.** `gh pr diff <pr>` or `git diff <base>...<head>`. Read it; do not write from the
  file list alone.
- **The ticket**, if any: from the branch name, the conversation, or the existing body.
- **What was run** against this change: tests, typecheck, lint. If you do not know, say so in
  the body rather than guessing.
- **Whether this PR is one layer of a stack.** If it is, the calling workflow usually passes
  extra notes (what lower layers provide, what stays unused until a higher layer, co-dependent
  PRs). Fold those into Overview and Technical Solution as described below.

## Title

Descriptive, completes the sentence "This commit ...", names the affected package or component,
includes the ticket when there is one. Canva's common formats:

- `[JIRA-999] <description>`
- `<package>: <description> [JIRA-999]`

Good:

- `[PUB-212] Adds ScheduledPublish proto and regenerated bindings`
- `publish/server: adds SchedulerStore with DynamoDB implementation [PUB-212]`

Bad: `wip`, `part 2`, `update proto`, `more changes`. A reviewer scanning their queue should know
what the PR does from the title alone.

Do **not** put "(1/5)" style counters in the title. Stack order changes when layers are folded or
inserted, and stack tooling shows position in the body.

## Body

Start every body from `assets/pr-template.md` (copy it, keep its headings and order) and fill it
in for this PR only.

How to fill each section:

- **Overview.** Two or three sentences: what this PR changes and why. For a stack layer, also
  say what it builds on from lower layers and what is intentionally unused until a higher
  layer, so the reviewer does not ask for things that live elsewhere in the stack. If this PR
  cannot merge without another PR, say so here in one sentence naming the other PR.
- **Related Issue.** The Jira ticket as `[CA-1337](https://canvadev.atlassian.net/browse/CA-1337)`.
  If there is no ticket, remove the bullet rather than leaving the placeholder.
- **Type of Change.** Tick exactly one box with `[x]`, chosen for *this PR*, not the feature it
  belongs to. A refactor-only PR at the bottom of a feature stack is `Refactor`, not
  `New feature`.
- **UX Solution** or **Bugged Behaviour**, never both. Keep UX Solution when the change adds new
  behaviour and delete the Bugged Behaviour section; keep Bugged Behaviour (with Expected and
  Actual filled in) when the change fixes a bug and delete UX Solution. For a PR with no
  user-visible effect (helpers, schema, wiring), keep the section the overall work uses and
  write one line pointing to where the behaviour becomes visible.
- **Technical Solution.** The reviewer's guide to the diff: what changed, the shape chosen and
  why, anything they might question (a public API choice, a new dependency, a deliberately
  temporary shim). End with what was run: targeted tests, typecheck, lint. Be exact, and say so
  if the full suite was not run. If a notable share of the lines is generated, say how many and
  where.
- **Before vs After.** Leave the heading and its comment exactly as they are. The author adds the
  media personally.

Remove the HTML comments from sections you have filled in; leave the one under Before vs After.

## Applying it

Write the body to a temp file and apply title and body together:

```bash
gh pr edit <branch-or-number> --title "<title>" --body-file /path/to/body.md
```

When updating a PR that already has a body, start from the live one
(`gh pr view <pr> --json body -q .body`) so edits made in the browser survive, and preserve any
tooling blocks at the end of it (for example a `<pr-train-toc>` block) exactly as they are.

Never change draft status, reviewers, or assignees while doing this. Writing the description is
not a signal that the PR is ready; the author decides that.

## Reference files

- `assets/pr-template.md`: the PR body template to copy for every PR.
