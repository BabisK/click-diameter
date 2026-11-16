- source_spec: `_bmad-output/implementation-artifacts/spec-ci-github-actions-build-and-test.md`
  summary: The smoke configs are judged only by exit status, so a wrong-bytes regression in any covered element still goes green.
  evidence: `tests/run.sh:26-37` branches on `rc` alone and every `tests/configs/*.click` ends in `Print(...) -> Discard;` with no assertion, so changing the AVP length field or leaving the R bit set would still exit 0. Closing it means output assertions in `tests/`, which this spec freezes.
  resolution: Done — PR #2 (`95f494d`). `tests/smoke.bats` asserts the label, packet length and hex bytes of all six configs under bats-core; `tests/run.sh` retired. `avp-roundtrip`'s expectation is F-7's unpadded output and says so, so story 1-3 updates it.
- source_spec: `_bmad-output/implementation-artifacts/spec-ci-github-actions-build-and-test.md`
  summary: The workflow offers no manual dispatch inputs, so a Click ref cannot be pinned to bisect an upstream break.
  evidence: `workflow_dispatch` is declared with no `inputs`; the Click revision comes from `refs/heads/master` in the resolve step.
  resolution: Closed, will not be implemented (2026-11-16) — runs always build the latest Click master; pinning a ref to bisect upstream is deliberately out of scope, so a dispatch run is just a manual re-run of the master build. No workflow change.
- source_spec: `_bmad-output/implementation-artifacts/spec-ci-github-actions-build-and-test.md`
  summary: Nothing runs the workflow on a schedule, so a Click master break surfaces only when someone opens a PR.
  evidence: Triggers are `pull_request`, `push` to `master` and `workflow_dispatch`; upstream Click last moved in 2022, so a quiet week hides a break indefinitely.
- source_spec: `_bmad-output/implementation-artifacts/spec-ci-github-actions-build-and-test.md`
  summary: No failure diagnostics are printed, so a red run does not show the resolved Click commit, the cache-hit value or the toolchain.
  evidence: The workflow has no `if: failure()` step and no job summary; diagnosing an upstream Click break means reading the resolve and build logs by hand.
- source_spec: `_bmad-output/implementation-artifacts/spec-ci-github-actions-build-and-test.md`
  summary: actionlint runs only as a manual verification command, not as a CI job, so a future workflow edit can regress the YAML unnoticed.
  evidence: Verification pins `rhysd/actionlint:1.7.12` but nothing in `.github/workflows/` runs it; the label `ubuntu-26.04` is unknown to that release, so a CI job would need `-ignore ubuntu-26.04` until actionlint catches up.
- source_spec: `_bmad-output/implementation-artifacts/spec-ci-github-actions-build-and-test.md`
  summary: `AGENTS.md`, `tests/README.md` and `README.md` were not updated to mention the CI job or the committed line-ending policy.
  evidence: `AGENTS.md` "Running and verifying" still describes the recipe as a manual step, and `README.md`'s install section still omits `--with-click`/`--prefix` (finding F-13, owned by story 1.7).
