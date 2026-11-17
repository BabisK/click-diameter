<!-- BMad's deferred-work queue. Open items only, in the format below; never
     annotate an entry with its outcome. A closed item leaves this file and is
     recorded in the owning spec's Review Triage Log as a `deferred` row, with
     the pull request as evidence. -->

- source_spec: `_bmad-output/implementation-artifacts/spec-popstorepush-smp-safety.md`
  summary: >-
    The suite's default ten-second per-config timeout is marginal for
    identifiers-rated-source-pull-unique on a multithread Click at base clock.
  evidence: |-
    On this host at 3.19 GHz, click --simtime on
    tests/configs/identifiers-rated-source-pull-unique.click takes about 12.2 s
    with the current package and about 12.4 s with the 7ac78a9 module, while the
    plain (non-multithread) Click takes 6.0 s. click_timeout defaults to 10
    (tests/smoke.bats:83), so the run is killed and the test fails with exit
    124. The same test passed at 21:52 and failed at 22:13 with no code change,
    so the margin tracks CPU clock rather than either package. Found while
    verifying spec-popstorepush-smp-safety, not caused by it. Raising
    click_timeout, or making the RATE 10 simulated run cheaper, settles it.
  location: >-
    tests/smoke.bats:83, tests/configs/identifiers-rated-source-pull-unique.click
  severity: low
