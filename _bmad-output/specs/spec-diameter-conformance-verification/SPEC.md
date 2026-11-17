---
id: SPEC-diameter-conformance-verification
companions: [findings.md]
sources: []
---

> **Canonical contract.** This SPEC and the files in `companions:` are the complete, preservation-validated contract for what to build, test, and validate. Source documents listed in frontmatter are for traceability — consult them only if you need narrative rationale or prose color this contract intentionally omits.

# Diameter Conformance Verification Repair

## Why

A mandate to meet: the RFC 6733 conformance delivery (stories 3–9) is green, but its verification layer misreports the work. Two stories ship code while recording "no implementation was started"; the identifier test's equal-pair check compares numbers rather than identifiers; two acceptance claims — the padded `DiameterEncap` frame being walkable, and 37/30 equal identifiers on the baseline — are false; and the two subtlest invariants, the advance-on-emission counters and the seeded first frame, have no observer. The delivery also left a six-item deferred queue (DW-1 to DW-6): two observation gaps, a silent repeated-keyword rule, the Encap, PopStorePush and AvpEncap three-octet ceilings, and an unbounded generator count. Anyone auditing conformance from these artifacts is told the wrong thing, and the regressions those tests and guards exist to catch would pass.

## Capabilities

- **CAP-1**
  - **intent:** The identifier tests decide what they claim: the two fields differ as strings, each field steps by exactly one per emitted message, the first frame of a seeded writer is the pre-change frame, and the 2^20 end-to-end carry works.
  - **success:** The advance-on-refusal and seed+1 mutants fail the suite; the committed seed passes; a 1 048 577-message run passes in the suite.
- **CAP-2**
  - **intent:** A writer whose buffer extension fails drops the packet instead of dereferencing null.
  - **success:** Every `push()`/`put()` in the touched data paths (and the identical `DiameterAvpEncap` site) tests for null and returns 0; the build is warning-free and the suite green.
- **CAP-3**
  - **intent:** Every public claim about the changed elements matches observed behaviour.
  - **success:** The `DiameterEncap` page and README say padding fixes the header rule only and that an AVP reader drops a non-AVP body; the end-to-end text describes a counter with a 12/20 presentation and no RFC time split; the reader pages list the flag reason before the AVP reason; the README names all four refusal families; `tests/README.md`'s counts and "prints bytes" sentence match the configs.
- **CAP-4**
  - **intent:** Stories 6 and 9 and the deferred ledger tell the truth about the shipped tree.
  - **success:** Neither story says "planning only"; each carries an implementation record, a suite count measured at the reviewed tree, and a review triage; the ledger header no longer says "Presently empty", no entry is truncated, and every location resolves.
- **CAP-5**
  - **intent:** The six deferred items are closed: an M=1 AVP and a zero `RANDUINT32` draw are observed, a repeated keyword is refused package-wide, and the Encap, PopStorePush and AvpEncap three-octet ceilings and the `RAND*STRING` cap are enforced.
  - **success:** The pre-change package shows the wrapped Lengths, the last-wins keyword and the late generator drop; the fixed package drops or refuses each at its configured point; the full suite passes with the new configs.

## Constraints

- One pull request on `spec/diameter-rfc-conformance`; no new branch.
- Identifiers stay seeded from `click_random()` under a fixed `RandomSeed`: one draw per field at initialization, then a counter advance per emitted message, so the seeded bytes are reproducible and may be pinned; the pins are the RNG's output for `SEED 12345`, not a libc-independent constant.
- No wire-format change. The only behaviour change is the allocation-failure null check; `DiameterEncap`'s padding stays because `SPEC-diameter-rfc-conformance` CAP-2 pins it.
- The man-page phrases `seeded once from click_random()` and `unique for the first 2^32 messages of a run` stay, because `tests/manpages.bats` asserts them.
- Tabs for indentation; warning-free at `-Wall -Wextra`; the full bats suite green.
- A repeated keyword fails configuration naming it (the user's resolution for DW-2); a `RAND*STRING` count is capped at 16,777,184 (16,777,180 with the vendor header); a PopStorePush overflow keeps the stored AVP.

## Non-goals

- No change to the padding decision or the three `encap-padding*` configs' bytes.
- No new element, argument, RNG or CI job.
- No rewrite of `SPEC-diameter-rfc-conformance`'s capabilities; only its success-signal exception and a recorded change.
- No load test beyond 2^20 + 1 messages.

## Success signal

`bats --tap tests` exits 0 with the new configs and assertions; the advance-on-refusal and seed+1 mutants fail their checks; the pre-change package fails the first-frame and consecutiveness assertions; the six deferred configs fail on the pre-change package (wrapped Lengths, last-wins keyword, late generator drop) and pass or refuse on the fixed one; and no story, README, man page or ledger entry contradicts the tree.

## Assumptions

- Click's RNG with `RandomSeed(SEED 12345)` is stable on the CI image, so literal identifier bytes are a legitimate pin (user direction).
- Click's first glibc `random()` draw for `RandomSeed(SEED 808357014)` is zero, so that seed pins the zero `RANDUINT32` draw.
- The padded body that is not an AVP sequence is an accepted limitation, documented and pinned by a drop config, rather than a reason to reopen the padding decision.
