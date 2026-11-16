- source_spec: `_bmad-output/implementation-artifacts/spec-ci-github-actions-build-and-test.md`
  summary: The smoke configs are judged only by exit status, so a wrong-bytes regression in any covered element still goes green.
  evidence: `tests/run.sh:26-37` branches on `rc` alone and every `tests/configs/*.click` ends in `Print(...) -> Discard;` with no assertion, so changing the AVP length field or leaving the R bit set would still exit 0. Closing it means output assertions in `tests/`, which this spec freezes.
- source_spec: `_bmad-output/implementation-artifacts/spec-ci-github-actions-build-and-test.md`
  summary: The workflow offers no manual dispatch inputs, so a Click ref cannot be pinned to bisect an upstream break.
  evidence: `workflow_dispatch` is declared with no `inputs`; the Click revision comes from `refs/heads/master` in the resolve step.
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
