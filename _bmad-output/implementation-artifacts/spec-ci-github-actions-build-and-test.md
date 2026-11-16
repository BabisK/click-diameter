---
title: 'Build and test the package on every pull request'
type: 'chore'
created: '2026-11-16'
status: 'done'
route: 'dispatch'
review_loop_iteration: 0
baseline_commit: '8f36893ec2f13e0926ba73dca3378aead48d0153'
context: []
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** The build-and-test recipe lives only in `AGENTS.md` and `tests/README.md`, so it runs when someone remembers. A PR can break compilation or a smoke config and still merge. The line-ending policy is equally unstated: LF is what the blobs happen to hold, and the CRLF a Windows checkout gets comes from a local `core.autocrlf=true`, not from the repository.

**Approach:** Add one GitHub Actions workflow that builds Click (userlevel driver, upstream master) into a stable prefix, builds and installs this package against that prefix, and runs `tests/run.sh` — on every pull request and every push to `master`. Commit a `.gitattributes` stating the line-ending policy: LF in the repository, CRLF on Windows checkouts.

## Boundaries & Constraints

**Always:** run on `ubuntu-26.04`; configure Click `--enable-userlevel --disable-linuxmodule` so the package never attempts a kernel-module build; give `--with-click` and `--prefix` the same value so `require(diameter)` resolves; pass the `click` binary path to `tests/run.sh`; keep third-party actions to `actions/checkout` and `actions/cache`; default `GITHUB_TOKEN` with `contents: read`; `.gitattributes` uses `* text=auto` and nothing narrower.

**Never:** change anything under `src/`; build the kernel module; run `tests/known-defects/` (they abort or hang on purpose); add branch-protection settings (repo settings, not code); add secrets or push to the repo; rewrite history to renormalize (unnecessary — the index is already LF).

## Decisions

- **Runner:** `ubuntu-26.04` (gcc 15.2), verified end to end rather than `ubuntu-latest`, so a GitHub image migration cannot change the compiler under you.
- **Triggers:** `pull_request` (any branch), `push` to `master`, `workflow_dispatch`.
- **Click revision:** `kohler/click` master HEAD, resolved each run; the cache key carries that commit, so upstream breakage surfaces as a cache miss and a failing Click build.
- **Line endings:** `* text=auto`. All 64 tracked files are already `i/lf`, so no renormalization commit is needed.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| PR opened or updated | any `pull_request` event | all steps run; green only when all six configs pass | failing config fails the job |
| Package does not compile | source error in `src/` | job fails at the package build step, before tests | make's exit status fails the step |
| Click master unchanged | cache hit for the resolved commit | Click build and install skipped; package still rebuilt | n/a |
| Click master advanced | cache miss | Click rebuilt and reinstalled, then the package | n/a |
| Click itself fails to build | upstream breakage | job fails inside the Click steps, not attributed to this package | n/a |
| Config hangs | a config that loops | `run.sh`'s 10 s `timeout` kills it and reports `FAIL <name>` | non-zero exit fails the job |
| Windows clone, default git config | `* text=auto` | text files checkout CRLF; blobs stay LF | n/a |

</frozen-after-approval>

## Code Map

- `.github/workflows/` — absent today; the workflow file is the only new CI file.
- `.gitattributes` — absent today. Verified state: `git ls-files --eol` reports 64 files, all `i/lf`; the CRLF working tree comes from local `core.autocrlf=true`.
- `tests/run.sh` — entry point: `$1` is the `click` binary, exits `2` if it is not executable, runs each `tests/configs/*.click` under `timeout 10`, prints `PASS`/`FAIL <name>`, exits non-zero on any failure. Do not modify.
- `tests/configs/*.click` — six configs, each opening with `require(diameter)`, so the package must be installed into the same prefix as `click`.
- `configure.ac` — `--with-click=DIR` needs `DIR/share/click/config.mk` and aborts without it; `--prefix` picks the install dir. Do not modify.
- `Makefile.in` — `MAKE_UPACKAGE`/`MAKE_KPACKAGE` come from Click's `config.mk`; `--disable-linuxmodule` leaves `CLICK_HAVE_LINUXMODULE_DRIVER=0`, so only `diameter.uo` is built. Do not modify.
- `.gitignore` — already covers `configure`, `Makefile`, `*.uo`, `elementmap-diameter.xml`; no change needed.
- `AGENTS.md` "Running and verifying" — the canonical recipe, including both `--with-click` and `--prefix`.

## Tasks & Acceptance

**Execution:**
- [x] `.github/workflows/build-and-test.yml` — create the workflow: `pull_request`, `push` to `master`, `workflow_dispatch`; `permissions: contents: read`; `concurrency` cancelling superseded runs; `timeout-minutes: 30`; resolve Click master's SHA; restore or populate a cached Click install at `$HOME/click`; install `build-essential autoconf libpcap-dev`; configure/build/install Click; `autoconf` then `./configure --with-click=$HOME/click --prefix=$HOME/click`; `make -j"$(nproc)"`; `make install`; `tests/run.sh "$HOME/click/bin/click"`.
- [x] `.gitattributes` — one rule, `* text=auto`, so the repository states LF-in-repo and CRLF-on-Windows instead of inheriting it from each clone's `core.autocrlf`.

**Acceptance Criteria:**
- Given a pull request is opened or updated, when the workflow runs, then it builds Click, builds and installs the package, and executes all six configs from `tests/configs/`.
- Given a commit lands on `master`, when the push event fires, then the same job runs.
- Given all six configs exit 0, then the job is green.
- Given any config fails or hangs, then the job fails and the log contains `FAIL <config name>`.
- Given the package fails to compile, then the job fails before the test step runs.
- Given the workflow file is on the default branch, then the check appears on every new pull request and can be run from the Actions tab.
- Given a fresh Windows clone with default git config, when text files are checked out, then they carry CRLF while the stored blobs stay LF; a fresh Linux clone checks out LF and builds unchanged.

## Implementation Notes

- Click is pinned to the commit that was resolved, not to whatever `master`
  points at when the clone happens: `git init` + `git fetch --depth 1 <sha>` +
  `checkout --detach FETCH_HEAD`. Otherwise a push landing between resolution and
  clone would build one commit under another commit's cache key.
- The cache holds the whole `$HOME/click` prefix, so a hit also carries the
  package artifacts from the previous run. That is harmless: the package steps
  always run, and Click's `share/click/pkg-Makefile` overwrites `diameter.uo` and
  regenerates `elementmap-diameter.xml` from the sources on every `make install`,
  so nothing stale can survive a cache hit.
- The prefix is saved by an explicit `actions/cache/save` step right after a
  successful Click build, not by a restore action's post step, so a PR that
  fails later still keeps its Click build. The key carries a literal `v1` to
  bump whenever the Click configure invocation changes.
- Actions are on current majors: `actions/checkout@v7`, `actions/cache/restore@v6`
  with `actions/cache/save@v6`.
- actionlint 1.7.12 (current release) predates the `ubuntu-26.04` label and
  reports one `[runner-label]` error for it; `-ignore 'ubuntu-26'` exits 0, so
  there are no other findings. The label itself is valid per GitHub's hosted
  runner reference.
- Independent replay of the workflow's exact steps, on `ubuntu:26.04`, against
  the staged index (`git checkout-index`): LF checkout with the exec bit intact,
  `git ls-remote` resolving `9197a594`, `git fetch --depth 1 <sha>` +
  `checkout --detach FETCH_HEAD` succeeding, Click and the package building and
  installing, and all six configs passing (`TESTS EXIT: 0`).
- Matrix rows verified by execution: PR/`workflow_dispatch` wiring (actionlint),
  cache-miss rebuild, Click build failure path, and a hanging config
  (`FAIL hang.click (exit 124)` after 10 s, `rc=1`). Cache-hit skipping is the
  `if: steps.click-cache.outputs.cache-hit != 'true'` guard; "package does not
  compile fails before tests" is guaranteed by step order plus the runner's
  `bash -e`.
- Line endings: a clone with `core.eol=crlf` checks out `tests/run.sh` as CRLF
  while `git ls-files --eol` still reports `i/lf`; `git check-attr text` reports
  `auto`.

## Spec Change Log

Empty: no bad_spec loopback was triggered.

## Review Triage Log

One row per reviewer finding. `blind` = blind hunter, `edge` = edge-case hunter, `vgap` = verification-gap.

| # | Layer | Finding | Verdict | Evidence / disposition |
|---|-------|---------|---------|------------------------|
| 1 | blind | No assertion that the package built or installed; `onezero` is bash-only so `BUILD_USERLEVEL` could be 0 and `make` a no-op | false | Every config opens with `require(diameter)`; without an installed `diameter.uo`, `click` exits non-zero and `run.sh` reports FAIL, so a no-op build cannot go green. The replay installed `diameter.uo` and passed. |
| 2 | blind | The cached prefix can serve stale package artifacts | false | Click's `pkg-Makefile` makes `install`, `install-obj` and the element map depend on the phony `always` target, so `make install` overwrites `diameter.uo` and regenerates `elementmap-diameter.xml` every run (confirmed by the vgap layer). |
| 3 | blind/edge/vgap | The cache key ignores the Click configure flags, the image's libpcap/toolchain, and any cache format version | low | Real: the cache lookup is exact-key, so editing the flags silently reuses the old prefix. Fixed — key now carries a literal `v1` to bump with the configure invocation. |
| 4 | blind | On a cache hit the `--disable-linuxmodule` invariant is not re-applied | false | The cached prefix was produced by the same invocation under the same key; the build is skipped by design, and a flag change now requires a `v1` bump. |
| 5 | blind | `actions/cache` saves only on job success, so every failing PR push rebuilds Click | medium | Real and frequent (a red PR is the normal state). Fixed — `actions/cache/restore@v6` plus an explicit `actions/cache/save@v6` right after the Click build. |
| 6 | blind/edge | `git ls-remote` has no retry and `test -n` accepts junk, so one network blip fails the PR | low | Real. Fixed — three attempts, `^[0-9a-f]{40}$` required; verified in `ubuntu:26.04` against real and shimmed remotes. |
| 7 | blind | `workflow_dispatch` takes no inputs, so a Click ref cannot be pinned for bisecting | low | Deferred: a feature beyond the intent. |
| 8 | blind | No `schedule:` trigger, so upstream breakage surfaces only when a PR opens | low | Deferred: not asked for; upstream Click last moved in 2022. |
| 9 | blind | No `paths-ignore`, so docs-only PRs pay for a full Click build | false | The intent is CI on every pull request; ignoring paths would contradict it. |
| 10 | blind | `cancel-in-progress: true` also cancels in-flight `master` runs | false | `master` history is linear, so the run that survives tests a superset of the cancelled commit. |
| 11 | blind/vgap | The tests assert exit status only, so a wrong-bytes regression still goes green | medium | Real and pre-existing: `tests/run.sh` only branches on `rc`, and the configs end in `Print`. Deferred — the spec freezes `tests/`. |
| 12 | blind | Nothing asserts that six configs ran; deleting one still passes | low | Rejected: a hardcoded count in the workflow would break whenever a seventh config is added — a worse failure mode than the one it guards. |
| 13 | blind | `tests/known-defects/` is never exercised, so its table rots | false | The intent excludes them: several abort or hang by design. |
| 14 | blind | `run.sh`'s `timeout` is assumed, not guaranteed | false | `coreutils` ships on the pinned `ubuntu-26.04` image, so the no-timeout fallback is unreachable there. |
| 15 | blind/edge/vgap | `* text=auto` makes Windows checkouts CRLF, breaking an in-place WSL build; `eol=lf` would fix it | low | Rejected as out-of-intent: the human chose CRLF on Windows with that exact consequence stated, and the frozen block prescribes `* text=auto` and nothing narrower. `AGENTS.md` still documents the export step. |
| 16 | blind | `AGENTS.md`, `tests/README.md` and `README.md` are left contradicting the change | low | Deferred: docs follow-ups. The `README` install recipe is finding F-13, owned by story 1.7. |
| 17 | blind | The intent's premise only holds once the check is required | low | Rejected as out-of-intent: branch protection is a repository setting, explicitly out of scope and disclosed at approval. |
| 18 | blind | The spec lacks `## Spec Change Log` / `## Review Triage Log`; `## Decisions` is not a template section; status was stale | low | Rejected as a finding whose fix is a spec edit; both log sections are added here regardless. `## Decisions` records the approved answers to the Open Questions. |
| 19 | blind | Open Questions were deleted while real choices stayed unrecorded | false | The trigger, Click revision and line-ending choices were each asked and answered; the fourth is a GitHub settings action, not a spec choice. |
| 20 | blind | The spec exceeds the template's 1600-token budget | low | Rejected: the scope standard says neither limit is a gate. |
| 21 | blind | "ubuntu-26.04 (gcc 15.2)" and the migration claim are asserted, not verified | low | Rejected: gcc 15.2 was observed in the replay, and the claim is about image-family migration. Frozen wording; no code impact. |
| 22 | blind | The actionlint evidence uses a moving `:latest` tag and no job runs actionlint | low | Partly fixed — the Verification command now pins `rhysd/actionlint:1.7.12`. Running actionlint in CI is deferred: not asked for. |
| 23 | blind | No failure diagnostics, and the job name omits the package build | low | Job name fixed ("Build and test the package"). Diagnostics deferred. |
| 24 | blind | No Dependabot/Renovate, no `-Wall` signal, and the work is absent from `sprint-status.yaml` | low | Rejected: outside the intent; the epic status file tracks epic stories, not chores. |
| 25 | edge | A cache hit with an incomplete prefix leaves the package configure aborting on a missing `config.mk` | low | Rejected: the failure is loud and names the missing file, and the fix adds a branch for a state no run was shown to reach. |

## Verification

**Commands:**
- Materialize the staged tree (`git checkout-index -a --prefix=/tmp/tree/`, or a fresh clone once committed) and run the workflow's command sequence inside `ubuntu:26.04` (`CLICK_PREFIX=$HOME/click`) — expected: every stage runs, `PASS` six times, `TESTS EXIT: 0`. Verified against Click master `9197a594b1c314264935106297aff08d97cbe7ee`.
- `git ls-files --eol | grep -v '^i/lf'` — expected: no output (index still LF after the `.gitattributes` commit).
- `git check-attr text -- tests/run.sh` — expected: `text: auto`.
- `docker run --rm -v "$PWD:/repo" --workdir /repo rhysd/actionlint:1.7.12` — expected: the single diagnostic is `[runner-label]` for `ubuntu-26.04`, which that release predates; `-ignore ubuntu-26.04` exits 0, so there are no other findings.
- `git status --short` after a run — expected: only the two intended files, no build artifacts.
