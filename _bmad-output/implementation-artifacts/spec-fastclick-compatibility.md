---
title: 'Support and verify FastClick'
type: 'feature'
created: '2026-11-18'
status: 'done'
route: 'dispatch'
review_loop_iteration: 0
baseline_commit: '03b5f7706c9a125fb2c5d0c0b29c328f06b1baec'
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The package targets upstream Click only. FastClick 2.1 changes the default `TokenBucket` from jiffy ticks to microsecond ticks, so `DiameterRatedSource` does not compile against it; a cast-only fix compiles but schedules the timer 1000x too long. Neither CI nor the docs covers FastClick.

**Approach:** Convert the timer's tick count with `TokenBucket::parameter_type::timestamp()` so the bucket's own unit is used, add a deterministic simulated-time test that pins one token interval at 1 ms, document the FastClick build flags and the non-batching caveat, and add a CI job that builds FastClick `main` and runs the full suite.

## Boundaries & Constraints

**Always:** keep upstream Click behavior byte-identical; build FastClick from `tbarbette/fastclick` `main` resolved to a commit; configure it `--enable-userlevel --disable-linuxmodule --enable-user-multithread --enable-simtime --disable-verbose-batch`; run the full bats suite against the installed FastClick prefix; keep the existing `ubuntu-26.04`, `contents: read`, cache-by-SHA and failure-summary conventions.

**Never:** change element wire behavior or upstream test expectations; make FastClick a build requirement; add DPDK/Netmap, a third-party action or secrets; commit to `master`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Upstream Click | existing recipe | package builds; full suite passes | make/bats exit status fails the job |
| FastClick | `main` + flags above | package builds; full suite passes | make/bats exit status fails the job |
| FastClick without `--enable-simtime` | `click --simtime` | option rejected; suite fails | documented requirement |
| FastClick without `--disable-verbose-batch` | any smoke config | batching warning joins the output; byte-exact tests fail | documented requirement |
| Cast-only timer fix | `Timestamp::make_jiffies((click_jiffies_t) ...)` | frame 11 arrives 1 s after frame 10 | timing test fails |
| FastClick `main` advances | new commit | cache miss; FastClick rebuilt | failure names FastClick |
| Non-batch elements | any FastClick pipeline | warning unless verbose batch disabled; per-packet processing | documented limitation |

</frozen-after-approval>

## Code Map

- `src/diameterratedsource.cc:147` -- replace `Timestamp::make_jiffies(_tb.time_until_contains(1))` with `TokenBucket::parameter_type::timestamp(...)`; comment the jiffy/usec difference.
- `tests/configs/rated-source-timing.click` -- new config: `RATE 1000, LIMIT 12`, `Print(TIMESTAMP true)`; burst 10 makes frames 11 and 12 one 1 ms interval apart.
- `tests/smoke.bats` -- add one test near the rated-source tests; run with `run_click_simtime`, parse `timing:` timestamps, require both deltas in `[0.0005, 0.005]` s.
- `.github/actions/build-click/action.yml` -- add `repository` (default `https://github.com/kohler/click.git`) and `configure-args` (default the current `--enable-userlevel --disable-linuxmodule --enable-user-multithread`) inputs; use them in fetch/configure; update name/description.
- `.github/workflows/build-and-test.yml` -- add `resolve-fastclick` (`refs/heads/main`, 3 retries, SHA regex) and `fastclick` job (deps incl. `perl`, cache key `fastclick-${runner.os}-v1-<args-hash>-<sha>`, timeout 30, package build, `CLICK=$HOME/fastclick/bin/click bats --tap tests`, failure summary).
- `README.md` -- Requirements, a FastClick section after Build and install, a Tests sentence, a Known limitations paragraph.
- `tests/README.md` -- FastClick running subsection, CI note, config-table row.
- `AGENTS.md` -- append a FastClick section outside the `bmad:context` markers.

## Tasks & Acceptance

**Execution:**
- [x] `src/diameterratedsource.cc` -- use `TokenBucket::parameter_type::timestamp()` and comment why -- the only source change.
- [x] `tests/configs/rated-source-timing.click` -- add the timing config -- makes the unit bug observable.
- [x] `tests/smoke.bats` -- add the `rated-source-timing` test -- fails on a 1 s interval.
- [x] `.github/actions/build-click/action.yml` -- parameterize repository and configure args -- one action serves both forks.
- [x] `.github/workflows/build-and-test.yml` -- add `resolve-fastclick` and `fastclick` -- verifies the compatibility claim.
- [x] `README.md` -- document FastClick flags, the non-batching limitation and the `--enable-auto-batch=port` mitigation -- user-facing support.
- [x] `tests/README.md` -- document the FastClick test recipe and new config -- test-facing support.
- [x] `AGENTS.md` -- append the FastClick note outside the managed block -- guidance survives a context refresh.

**Acceptance Criteria:**
- Given upstream Click, when the package is built and the full suite (including the new timing test) runs, then it passes.
- Given FastClick built with the flags above, when the package is built and the full suite runs, then it passes.
- Given the cast-only timer fix, when the timing test runs, then it fails with a ~1 s interval.
- Given a pull request, when the workflow runs, then the `fastclick` job builds FastClick and the package and runs the full suite.
- Given a FastClick build or test failure, when the job fails, then the summary names the failing stage and the FastClick commit.
- Given the README, when a user looks for FastClick, then the build flags and the non-batching caveat are stated.

## Implementation Notes

- `src/diameterratedsource.cc` -- the timer now converts through
  `TokenBucket::parameter_type::timestamp()`; the comment names the jiffy/usec
  difference. Upstream Click's parameter type maps to `make_jiffies`,
  FastClick's to `make_usec`.
- `tests/configs/rated-source-timing.click` + `tests/smoke.bats` -- `RATE 1000,
  LIMIT 12` gives a burst of 10, so frames 11 and 12 are one 1 ms tick apart.
  The test splits seconds from subseconds before subtracting, so the epoch does
  not lose precision. Negative control: the cast-only form failed with
  `expected a 1 ms refill interval, got 1.001000005s`.
- `.github/actions/build-click/action.yml` -- `repository` and `configure-args`
  default to the old Click recipe, so the two existing Click jobs are unchanged;
  FastClick passes its own repository and the five flags.
- `.github/workflows/build-and-test.yml` -- `resolve-fastclick` resolves
  `refs/heads/main`; the `fastclick` job caches by that SHA and mirrors the
  existing failure summary with the FastClick commit.
- Verification: `CLICK=/tmp/opencode/click-mt/bin/click bats --tap tests` and
  `CLICK=/tmp/opencode/fastclick-prefix/bin/click bats --tap tests` both passed
  171/171; actionlint 1.7.12 (`-ignore ubuntu-26`) reported no findings.
- Matrix coverage: the two build rows are the two 171/171 runs; the cast row is
  the negative control above; the missing-flag rows were observed on the stock
  FastClick build (batching warnings broke 126 byte-exact tests) and its
  `--simtime` rejection; the moving-`main` and non-batch rows are the
  resolver/cache design and the documented limitation.
- Review patches: the FastClick cache key folds in a 12-char hash of
  `FASTCLICK_CONFIGURE_ARGS`; both CI test steps set
  `CLICK_REQUIRE_MULTITHREAD=1`; the action step names and the `configure-args`
  description were clarified; the README and `tests/README.md` recipes were made
  consistent and runnable. Re-verified after the patches: 171/171 on both trees
  with zero skips, and actionlint clean.

## Spec Change Log

## Review Triage Log

One row per reviewer finding. `blind` = blind hunter, `edge` = edge-case hunter, `vgap` = verification-gap. Patched findings are fixed in the same pass; rejected findings carry the evidence that settles them.

| # | Layer | Finding | Verdict | Evidence / disposition |
|---|-------|---------|---------|------------------------|
| 1 | blind | FastClick cache key is SHA-only, so a `configure-args` change can restore a prefix built with old flags | low | Real: the key at `build-and-test.yml:214` has no flags component and the action skips the build on a hit. Patch: fold a short hash of the configure args into the key, with one source of truth for the args. |
| 2 | blind | Action step names still say "Click" although the action serves FastClick too | low | Real log clarity: `action.yml:49,56,87`. Patch: rename to Click/FastClick. |
| 3 | blind | `configure-args` is unquoted, so a caller could repeat `--prefix` or pass a glob | low | Real only for a misused internal input; no current caller does. Patch: state in the input description that the action supplies `--prefix`. |
| 4 | blind | Timing test hardcodes burst frame indices 10/11, and the element does not document the burst formula | low | The test intentionally pins the RATE 1000 burst; the formula is `diameterratedsource.cc:62` and the config comment states the concrete value. Rejected: deriving the first gap would mask a burst change, and the spec pins burst 10. |
| 5 | blind | Burst comment states `rate/100` as a general rule | false | The comment names RATE 1000, where `rate/100` is correct; no bad outcome. Wording clarified with #6. |
| 6 | blind | "Same simulated instant" is really ~3 ns apart, and nothing asserts the burst | low | The first ten leave in one task loop and differ by nanoseconds; the test only needs the post-burst interval. Patch: say "within a few nanoseconds". |
| 7 | blind | The 1 ms window is 10x looser than the test name | false | The test is a gross-error guard for the 1000x cast, as the approved spec's Design Notes says; a 2x error is outside the intent. |
| 8 | blind | The awk trusts Print's `SEC.FRAC:` format without checking it | low | The format is fixed per build (`%09u` or `%06u`), and a change fails the test. Rejected: cosmetic error-message improvement, not a demonstrated defect. |
| 9 | blind | README says "two flags beyond the Click recipe" while the Click recipe omits `--enable-user-multithread` | low | Real: `README.md:39-41` versus `:91-101`; the local smp coverage differs. Patch: add the flag to the Click step and name the two FastClick-specific flags. |
| 10 | blind | `tests/README.md` FastClick snippet is not runnable (no clone/cd, `-j8`, `<package>`) | low | Real usability. Patch: mirror the README clone/cd sequence and use `-j"$(nproc)"`. |
| 11 | blind | "Known limitations" opens with "One open item remains" but now has two | low | Real: the new FastClick paragraph follows the F-16 text with no lead-in. Patch: name both limitations. |
| 12 | blind | Auto-batch recommendation is untested, and "neither flag changes a byte" covers it | false | The byte claim was verified locally with `--enable-auto-batch=port` (full suite green); the README only says CI builds with `--disable-verbose-batch`. |
| 13 | blind | Both spec log sections are blank | false | The Review Triage Log is populated by this step; the Change Log stays empty until a loopback. The fix would edit the spec. |
| 14 | blind | New job duplicates the resolver and failure summary | low | Real duplication, but the fix is a matrix/shared-summary refactor beyond the intent; the existing workflow already has per-job diagnostics. Rejected: more than a direct correction. |
| 15 | blind | "FastClick 2.1" is documented while CI follows `main`, with no version policy | low | The README already says CI builds `main` at a resolved commit and the failure summary names it; the Click docs use the same pattern. Rejected: no demonstrated defect. |
| 16 | blind | `perl` is added only to the FastClick job's dependencies | low | Real inconsistency: both jobs run `manpages.bats`. Patch: add `perl` to the Click job's dependencies. |
| 17 | edge | Omitting `--enable-user-multithread` from `configure-args` makes the `smp-*` tests skip | low | Same root as #20; no current caller omits it, but the new input can lose it. Patch with #20. |
| 18 | edge | Cache key reused after a repository or `configure-args` change | low | Same as #1; patch with #1. |
| 19 | edge | Mixed 6/9-digit fractions break the shared scale | false | Click prints one fixed precision per build (`%09u` or `%06u`); no mixed-width run exists, and the test passes on both. |
| 20 | vgap | The five `smp-*` tests skip silently if the build loses `--enable-user-multithread`, so CI can be green without two-thread coverage | medium | Pre-verified by the layer: deleting the flag leaves bats green with five skips. Patch: `CLICK_REQUIRE_MULTITHREAD=1` makes `smp_skip_or_fail` fail; set it in both CI test steps. |
| 21 | vgap | Cache key carries no fingerprint of `configure-args` | low | Same as #1; patch with #1. |

## Design Notes

`TokenBucket::parameter_type::timestamp()` is the only conversion that follows the bucket's own unit: upstream's `TokenBucketJiffyParameters` maps to `make_jiffies`, FastClick's `TokenBucketUsecParameters` to `make_usec`. A cast to `click_jiffies_t` compiles on both but reads FastClick's microseconds as milliseconds. The timing test pins the interval under `--simtime`, so it is deterministic and catches the cast.

## Verification

**Commands:**
- `./configure --with-click=$HOME/click --prefix=$HOME/click && make -j$(nproc) && make install && CLICK=$HOME/click/bin/click bats --tap tests` -- expected: full suite passes on upstream Click.
- `./configure --with-click=$HOME/fastclick --prefix=$HOME/fastclick && make -j$(nproc) && make install && CLICK=$HOME/fastclick/bin/click bats --tap tests` -- expected: full suite passes on FastClick.
- `CLICK=$HOME/fastclick/bin/click bats --tap --filter rated-source-timing tests` -- expected: passes with the fix; fails with a ~1 s delta on the cast-only variant.
- `docker run --rm -v "$PWD:/repo" --workdir /repo rhysd/actionlint:1.7.12 -ignore 'ubuntu-26'` -- expected: no findings.
- `git status --short` -- expected: only the intended files, no build artifacts.
