---
title: 'Enable multithreaded Click in CI so the SMP tests run'
type: 'chore'
created: '2026-11-17'
status: 'done'
review_loop_iteration: 0
followup_review_recommended: false
context: ['{project-root}/AGENTS.md']
warnings: []
deferred: []
---

# Enable multithreaded Click in CI so the SMP tests run

## Why

Story 1 made the three writers safe under Click's router threads and added three `smp-*` configs to prove it. CI builds Click with `--enable-userlevel --disable-linuxmodule`, which has no multithread support, so all three configs reported a skip and the gate proved only the single-threaded contract. Story 1 recorded that as a deferred item; the operator then asked for it to be closed.

## Change

- `.github/actions/build-click/action.yml` (the shared Click build, extracted by story 11) -- add `--enable-user-multithread` to the Click configure line, with a comment saying what it buys; bump both cache keys from `v1` to `v2` so the next run rebuilds the prefix instead of restoring one built without the flag (the comment above the keys requires the bump whenever the configure invocation changes).
- `_bmad-output/specs/spec-diameter-rfc-conformance/SPEC.md` -- narrow the CI non-goal to this one change.
- `tests/README.md` -- CI now runs the two-thread tests; only ThreadSanitizer stays local.
- `_bmad-output/specs/spec-diameter-rfc-conformance/stories.yaml` -- story 10, this change.

## Verification

- Two-CPU pin (`taskset -c 0,1`) against a `--enable-user-multithread` Click: `bats --tap tests` -> 94 passed, 0 failed, 0 skipped, 21.1 s wall. The three `smp-*` tests ran rather than skipped, with `smp-push-avp` producing 1000 + 999 frames from the two sources.
- The three `smp-*` tests were also checked on one CPU by story 1 (`taskset -c 0`: 1000 + 705 frames), so the floors are not tuned to a workstation.
- `./configure --enable-userlevel --disable-linuxmodule --enable-user-multithread` is the exact combination the workflow now uses; it configures cleanly, and a full build of it is what `/tmp/opencode/click-mt` already is.
- Workflow YAML parses, and both cache keys carry `v2`. The line now lives in the composite action both jobs use, so it cannot drift between them.

## Risks

- The first run after this change rebuilds Click instead of hitting the cache (a few minutes), because the cache key moved.
- On a single-core runner the two tests that need the producers to overlap could fail; GitHub's hosted runners have at least two vCPUs, and the one-CPU check above passes with the story-1 floors.
- ThreadSanitizer is still not in CI, so `DiameterPushAVP`'s shared-`String` race remains caught only by a local run (story 1, deferred item).

## Auto Run Result

Status: done

Implemented directly by the operator's request, outside the build-auto loop: the change is a three-line workflow edit plus the cache-key bump it forces, and it closes deferred items of story 1 rather than deriving new behaviour. Evidence in Verification above.
