# Splitting a large change into PRs and commits

## What "atomic" means at each level

**An atomic PR** is a change that:

1. Does one thing you can name in a sentence ("adds a retry helper to `http/client`").
2. Can be merged on its own without breaking trunk: it builds, tests pass, nothing user-facing
   regresses. Code that is not yet called is fine. A half-wired feature that throws is not.
   When this is not achievable but the split still makes review clearer, keep the split and
   mark the PRs as co-dependent (in the plan, in each PR's Overview, and at the end of the final
   report) so nobody merges one half alone.
3. Carries the tests that prove it, so the reviewer can approve it without reading the next PR.
4. Fits in one reviewer's head: about 300 changed lines, never more than 500.

**An atomic commit** is one step inside a PR that:

1. Changes one thing for one reason. If the message needs "and", split it.
2. Leaves the tree buildable (tests may be red only when the next commit is "add tests" and the
   PR as a whole is green).
3. Can be reverted alone without dragging unrelated changes with it.

A reviewer who reads a PR commit by commit should be able to follow the author's reasoning. That
is the test: does the commit list read like the steps you would explain at a whiteboard?

## Ordering PRs: bottom-up by dependency

The stack is a dependency chain, so PR n may use anything from PRs 1 to n-1 and nothing above.
Typical order:

1. **Foundation**: shared helpers, new types, proto or schema changes, config plumbing,
   changes to an existing independent library to accommodate the feature.
2. **Core logic**: the new component, service method, or algorithm, with its unit tests.
3. **Wiring**: connecting the core to its callers, dependency injection, routes, handlers.
4. **Enablement**: the small change that makes it reachable, such as a feature flag default,
   menu entry, or route registration. Keeping this last and tiny means the feature can be turned
   on with a one-line revertable PR.

Pure refactors and mechanical changes that prepare the ground (renames, moves, extracting an
interface) go as early as possible, often as PR 1, because they are easy to review in isolation
and painful to review mixed with behaviour changes.

## Axes to split along

The most productive axes are:

- **Client versus server.**
- **Logic versus data or schema** (protos, migrations, fixtures).
- **Logic versus pure refactoring** (file moves, renames, extract method).
- **Impactful code that needs careful thought versus conventional, non-contentious code.**
- **Widget versus harness page versus tests** (frontend).

Example: implementing feature Foo could land as

- Add Foo to proto files.
- Add Foo to the schema or data layer.
- Implement how Foo works, with tests.
- Configure, glue, and wire Foo up to its parent.

## Sizing rules

- Count changed lines as additions + deletions from `git diff --numstat`. Binary files count as
  zero but should be mentioned.
- Target 300, ceiling 500. Over 300 is a prompt to look for a seam; over 500 is a defect in the
  plan unless the file is indivisible.
- Generated files, lockfiles, and snapshots inflate the count without adding review load. Keep
  them with the change that caused them, but do not let them force an awkward split. Say in the
  PR body how many of the lines are generated.
- Do not go below "meaningful". A 15-line PR that is only a setup step for the next PR belongs in
  the next PR. If the whole change is under about 400 lines and one concern, it may not need a
  stack at all; say so instead of splitting for its own sake.

## Splitting one file across PRs or commits

Sometimes one file holds several concerns: a helper added at the top, a method rewritten in the
middle, a call site changed at the bottom. Each belongs with its own PR. The reliable technique:

1. The working tree has the final version of the file.
2. Edit the file down to the *intermediate state*: the final version with the later concerns'
   hunks removed (or reverted to the trunk version of those hunks).
3. Stage and commit that.
4. Restore the final version: `git checkout <orig>-full -- <path>`.
5. The remaining diff for that file is exactly the later concerns.

Editing a file to a described state is something you do well; crafting partial patch files by
hand is not. The end-of-build check (`git diff <orig>-full` is empty) catches any slip.

## Commit messages

Subject line in the imperative, completing the sentence "This commit ...", naming the package or
component where it helps. Body explains *why* and anything non-obvious, wrapped at 72 columns.
Skip the body for genuinely self-explanatory mechanical commits.

```
http/client: add RetryPolicy with exponential backoff

Foo needs to survive transient 503s from the media service. The existing
client has no retry hook, so this adds an opt-in policy rather than
changing default behaviour for other callers.
```

Bad subjects: "soft fail", "Wire in resolution", "changed to 5 minutes",
"Remove more logs". They name neither the affected component nor the effect.

## Commit boundaries inside a PR

Typical commit sequence for a "core logic" PR:

1. `foo: extract FooValidator from FooService` (refactor, no behaviour change)
2. `foo: implement FooService.apply with per-item rollback` (behaviour)
3. `foo: add FooService tests for apply and rollback paths` (tests)

Keep separate:

- Mechanical changes (rename, move, format) from any behaviour change, so the reviewer can skim
  the mechanical commit and read the real one.
- Each component's change from its tests, so the reviewer can read the implementation first and
  then check the tests against their own expectations.
- Changes to different components, even when small. Two 40-line commits are easier to review and
  revert than one 80-line commit with two subjects.

## Worked example

Original change: 1,400 lines across 26 files implementing "scheduled publish" for designs.

| # | Branch | Lines | Commits |
|---|--------|-------|---------|
| 1 | `maxx/PUB-212-1-schedule-proto` | 180 | add ScheduledPublish proto; regenerate bindings |
| 2 | `maxx/PUB-212-2-scheduler-store` | 310 | add SchedulerStore interface; add DynamoDB implementation; add SchedulerStore tests |
| 3 | `maxx/PUB-212-3-publish-worker` | 420 | extract PublishRunner from PublishService (refactor); add ScheduledPublishWorker; add worker tests |
| 4 | `maxx/PUB-212-4-api-wiring` | 290 | add schedulePublish RPC handler; register handler and wire store and worker; add handler tests |
| 5 | `maxx/PUB-212-5-enable-flag` | 40 | add scheduled_publish feature flag default off; add flag to editor publish menu |

PR 3 is over the target but under the ceiling because the worker and its runner refactor are
one concern; the body says so. PR 5 is tiny on purpose: it is the switch.
