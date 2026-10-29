---
name: write-pr-description
description: >
  Instructions for writing the description (body) of a GitHub pull request from its diff, using
  the body template in the assets folder (Overview, Related Issue, Type of Change, UX Solution or
  Bugged Behaviour, Technical Solution, Before vs After). Produces the markdown body only. 
  Use this whenever the user asks to write, fill in, draft, update, or improve a PR
  description or PR body, asks to "describe this PR" or "fill in the PR template", or when
  another skill needs a body for a PR it is about to open or update.
---

# Write a PR description

A PR description is the reviewer's way into the diff. It tells them what changed, why, and what
was checked, so they can review the change instead of reverse-engineering it. This skill turns a
diff plus whatever context the caller provides into a filled-in body.

The output is **the body as markdown, and nothing else**. Return it to the caller (write it to
the path they named, or show it in the conversation).

## Inputs

Before writing, know:

- **The diff for this PR only.** `gh pr diff <pr>`, or `git diff <base>...<head>` where `<base>`
  is the PR's base branch (not trunk, if the PR is a layer of a stack). Read it; do not write
  from the file list alone.
- **The ticket**, if any: from the caller, the branch name, the conversation, or the existing
  body.
- **What was run** against this change: tests, typecheck, lint. If you do not know, say so in
  the body rather than guessing.
- **Caller context**, if any. When the PR is one layer of a stack the caller passes notes such
  as what lower layers provide, what this layer leaves unused until a higher layer, which PRs it
  must merge together with, and which section (UX Solution or Bugged Behaviour) the overall work
  uses. Fold these into the sections described below; do not add new sections for them.

## Body

Start from `assets/pr-template.md` (copy it, keep its headings and order) and fill it in for
this PR only.

How to fill each section:

- **Overview.** Two or three sentences: what this PR changes and why. If the caller said this
  PR builds on earlier PRs or deliberately leaves something unused until a later one, say so
  here, so the reviewer does not ask for things that live elsewhere. If this PR cannot merge
  without another PR, say so here in one sentence naming the other PR.
- **Related Issue.** The ticket as `[TICKET-123](<link to the ticket>)`, using the tracker's
  link format for this repository. If there is no ticket, remove the bullet rather than leaving
  the placeholder.
- **Type of Change.** Pick a type of change for _this PR_, not the feature it
  belongs to. A refactor-only PR at the bottom of a feature stack is `Refactor`, not
  `New feature`.
- **UX Solution** or **Bugged Behaviour**, never both. Keep UX Solution when the change adds new
  behaviour and delete the Bugged Behaviour section; keep Bugged Behaviour (with Expected and
  Actual filled in) when the change fixes a bug and delete UX Solution. For a PR with no
  user-visible effect (helpers, schema, wiring), keep the section the overall work uses and
  write one line pointing to where the behaviour becomes visible.
- **Technical Solution.** The reviewer's guide to the diff: what changed, the shape chosen and
  why, anything they might question (a public API choice, a new dependency, a deliberately
  temporary shim).
- **Before vs After.** Leave the heading and its comment exactly as they are. The author adds the
  media personally.

Remove the HTML comments from sections you have filled in; leave the one under Before vs After.

## Writing well

- Write for a reviewer who has not read the conversation. Name files and functions only where
  the reviewer needs to go; describe the rest in words.
- Say why, not just what. The diff already shows what.
- Do not pad. A small PR gets a short body; empty sections are removed, not filled with filler.
- Do not claim checks you did not run.

## Updating an existing body

When asked to improve a body that already exists, check against the most up to date version
by using the GitHub CLI to fetch the latest version. Keep anything the author wrote that is
still true. Return the whole body, not a diff of it. Leave any trailing tooling block
(for example `<pr-train-toc>`) out of your output; the caller re-attaches it.

## Reference files

- `assets/pr-template.md`: the PR body template to copy for every PR.
