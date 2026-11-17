---
title: 'Gate the two-thread configs on ThreadSanitizer in CI'
type: 'chore'
created: '2026-11-17'
status: 'done'
review_loop_iteration: 0
followup_review_recommended: false
context: ['{project-root}/AGENTS.md']
warnings: []
deferred: []
---

# Gate the two-thread configs on ThreadSanitizer in CI

## Why

Story 1 removed per-packet writes from three element members and proved it with `smp-*` configs. Two of those configs fail on the racy package because their Length and AVP Length derive from the packet. `DiameterPushAVP` is different: its AVP Length comes from configuration, so every frame it appends has the same shape whichever thread wins, and a shared-`String` corruption still looks like hex output. ThreadSanitizer was the only detector, and it was a hand-run procedure — the last manual edge check in this story's verification.

## Change

- `tests/tsan-check.sh` -- runs each config on two router threads under a ThreadSanitizer build and fails when a race's racing access (`#0` frame) is inside `src/diameter.*`. Judges reports, not the sanitizer's exit status, because Click races its own shutdown bookkeeping and exits 66 on a clean package. Refuses to run against a module that does not link `libtsan`, which is the trap a plain `make install` into a sanitizer prefix leaves.
- `.github/workflows/build-and-test.yml` -- new `thread-sanitizer` job: a sanitized Click (`-fsanitize=thread -g -O1`), its own cache key `click-tsan-<os>-v1-<sha>`, the package rebuilt with the sanitizer flags, then the three configs through the script.
- `.github/actions/build-click/action.yml` -- the Click build both jobs now share: restore, fetch at the resolved commit, configure with `--enable-userlevel --disable-linuxmodule --enable-user-multithread`, build, install, save. Inputs are the commit, the prefix name, the cache key and the compiler flags, so the sanitizer job runs the same recipe with instrumentation instead of a copy of it. A `resolve-click` job resolves the commit once and both jobs consume it, which removes the duplicated loop and fetch.
- The existing build job keeps its own steps for dependencies, the package build and the suite; only the Click build and the commit resolution moved.
- `_bmad-output/specs/spec-diameter-rfc-conformance/SPEC.md` -- the CI exception now covers both jobs.
- `tests/README.md` -- the ThreadSanitizer paragraph describes the job, the judgement rule and a local reproduction recipe instead of calling the check local-only.
- `_bmad-output/specs/spec-diameter-rfc-conformance/stories.yaml` -- story 11, this change.

## Verification

Against a fixed package built with `-fsanitize=thread`, through the exact script CI runs:

```
ok tests/configs/smp-avpencap.click
ok tests/configs/smp-encap.click
ok tests/configs/smp-push-avp.click
exit 0
```

Against the package at `5af853c` in the same prefix, the gate fails and names the defect:

```
FAIL tests/configs/smp-push-avp.click: click exited 134 under ThreadSanitizer
SUMMARY: ThreadSanitizer: heap-use-after-free include/click/string.hh:272 in String::deref() const
FAIL tests/configs/smp-encap.click: a racing memory access is inside this package:
  #0 DiameterHeader::setLength(unsigned int) src/diameter.hh:98
FAIL tests/configs/smp-avpencap.click: a racing memory access is inside this package:
  #0 AvpHeader::setLength(unsigned int) src/diameter.hh:199
exit 1
```

The plain job still passes with the same tree: 94 tests, 0 skipped, on a two-CPU pin against a `--enable-user-multithread` Click. The workflow parses as YAML with three jobs (`resolve-click`, `build-and-test`, `thread-sanitizer`), the action parses as a composite action, every `run` step in it declares a shell, both jobs pass only declared inputs, and no resolve loop or Click fetch remains inline. Both modes of the action's build step were executed locally with its exact shell: empty flags give a Click whose binary does not link `libtsan`, and the sanitizer flags give one that does.

Note which frames the racy run reports: `src/diameter.hh`, not the `.cc` files, because the setters are inline and land inside the element's `simple_action()`. A gate that matched only `diameter*.cc` would have passed the racy package, so the script matches `src/diameter.*`.

## Risks

- The sanitizer job adds a second Click build to CI: on a cache miss that is minutes, on a hit it is the package build plus about a minute of instrumented runs. The job has its own 45-minute timeout and its own cache key, so a sanitizer break cannot mask the plain job.
- Instrumented Click is slow and noisy; `TSAN_OPTIONS=halt_on_error=0:exitcode=0` keeps a run going after Click's own reports and makes a clean run exit 0, so a non-zero status means a crash or a configuration failure.
- The gate trusts the `#0` frame as the racing access. TSan prints one `#0` per access and they are inside report blocks, so Click-core races whose callers include this package's elements — `DiameterRatedSource::run_task` reaching `please_stop_driver` — do not trip it.

## Auto Run Result

Status: done

Implemented directly by the operator's request, on story 1's branch. The gap it closes was recorded as story 1's remaining detection deferral; evidence in Verification above.
