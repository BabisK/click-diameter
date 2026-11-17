# Conformance Verification Repair — Findings

Source: the adversarial, edge-case and verification-gap review of stories 3–9 on
`spec/diameter-rfc-conformance`, every entry re-measured against a build of the
branch (warning-free at `-Wall -Wextra`, suite 149/149) and, where useful,
against the pre-change package in `/tmp/opencode/s8b-base-prefix/lib`.

Severity is the impact if the item ships as-is. Locations are at the reviewed
tree (merge `39efb5e`).

## V-1 — The identifier helper compares numbers, not identifiers (medium)

- **Where:** `tests/smoke.bats:216` — `equal=$(awk '$7 == $8' ...)`.
- **Symptom:** awk types a hex field that looks like scientific notation
  (`216e0403`) as a number; two different identifiers both become infinity and
  compare equal.
- **Evidence:** the pre-change stream with `SEED 12345` reports 30 (RatedSource)
  and 37 (Encap) "equal" frames; a string comparison reports 0 and 0. The
  current code with `SEED 10` reports 377 false equal pairs and 0 by string.
  The committed seed passes only because its hbh window contains no
  numeric-looking field.
- **Fix:** compare strings (`($7 "") == ($8 "")`).
- **Capability:** CAP-1.

## V-2 — Story 9's 37/30 equal-pair baseline is the same artifact (medium)

- **Where:** `stories/9-make-identifiers-unique-within-a-run.md:18`, `:37`,
  `:76`, `:86`; `tests/README.md:83`.
- **Symptom:** the problem statement and the negative control quote "37 and 30
  frames carrying equal identifiers", which a string comparison shows is 0/0.
- **Evidence:** `awk '$7 == $8'` over the two pre-change runs gives 37 and 30;
  `awk '($7 "") == ($8 "")'` gives 0 and 0. The duplicate-value counts (11/7
  Encap, 17/13 RatedSource) reproduce and are the real defect.
- **Fix:** correct the numbers, keep the duplicate-value motivation, and drop
  the equal-pair half of the negative control or measure it as strings.
- **Capability:** CAP-4.

## V-3 — The seeded first frame is not pinned (medium)

- **Where:** `tests/smoke.bats:161-188` (`expect_seeded`); story 9 `Always` and
  acceptance criterion at `:24` and `:78`.
- **Symptom:** the story promises "the first message of `randomness-encap` and
  `randomness-rated-source` keeps the bytes it emits today", but every seeded
  test regexes the identifiers.
- **Evidence:** the pre-change package and this tree both print
  `16d5a847 3328a195`; a build seeding with `hbhStart + 1` passes 28/28 of the
  encap/identifier/randomness/smp tests while renumbering every run.
- **Fix:** pin the literal first frame of both writers, plus the mixed config
  below.
- **Capability:** CAP-1.

## V-4 — Advance-on-emission has no observer (medium)

- **Where:** `src/diameterratedsource.cc:112-129`, `:147-154`;
  `tests/smoke.bats:198-222`; `tests/README.md:84`, `:335`; story 9 `:110`.
- **Symptom:** the claim "a counter that steps on a refused token fails the
  frame count" is false: the mutant still emits LIMIT frames with LIMIT
  distinct values.
- **Evidence:** the mutant that hoists `nextHbh()`/`nextE2e()` above
  `_tb.remove_if(1)` passes `identifiers-rated-source-unique` and both
  `randomness-rated-source*` tests.
- **Fix:** assert consecutiveness from the first/last value plus the count and
  distinctness (portable bash base-16 arithmetic; no `strtonum`).
- **Capability:** CAP-1.

## V-5 — The 2^20 end-to-end carry is never crossed (medium)

- **Where:** `src/diameter.hh:36-40`, `:65-71`; `README.md:308-313`; the
  `identifiers-*` configs.
- **Symptom:** the story's stated reason for the 12/20 split — the epoch
  advancing when the low 20 bits wrap — is exercised by no test; the largest
  run is 240 000 messages.
- **Evidence:** a `nextE2e()` that masks to the low 20 bits without carrying
  passes the suite; a 1 048 577-message run takes ~2.4 s.
- **Fix:** add `identifiers-encap-wrap.click` at `LIMIT 1048577` and a
  single-run distinctness/consecutiveness assertion.
- **Capability:** CAP-1.

## V-6 — Moving the draws changes a mixed seeded config's bytes (medium)

- **Where:** `src/diameterencap.cc:63-74`, `src/diameterratedsource.cc:74-91`.
- **Symptom:** a seeded writer now consumes two draws at initialization instead
  of two per message, so a downstream `RAND*` consumer shifts from the second
  message on; nothing documents or pins it.
- **Evidence:** with `SEED 12345`, Encap then `PushAVP(RANDHEXSTRING 8)` prints
  `39354535 32303938` on the pre-change package and `42313935 45353230` now
  (frame 2). `SPEC-diameter-rfc-conformance` says well-formed input keeps its
  bytes.
- **Fix:** state the exception in the README and the SPEC success signal, and
  pin a mixed seeded config.
- **Capability:** CAP-1, CAP-3.

## V-7 — Unchecked buffer extension dereferences null (medium)

- **Where:** `src/diameterencap.cc:99-105` (new `put` after the existing
  `push`), `src/diameterpushavp.cc:235` (the new ceiling admits a 16 MB
  append); the same pattern at `src/diameteravpencap.cc:60`.
- **Symptom:** `WritablePacket::put()` returns null and frees the packet when
  its copy cannot be allocated; the next line dereferences it.
- **Evidence:** `click/packet.hh` documents `if (!q) return 0;`. Reachable in
  principle on any padded or maximal append.
- **Fix:** test the result and `return 0` at all three sites.
- **Capability:** CAP-2.

## V-8 — Padding does not make the Encap frame walkable (medium)

- **Where:** `src/diameterencap.cc:89-105`;
  `tests/configs/encap-padding.click`; story 6 at `:36` and `invoke_dev_with`
  in `stories.yaml`.
- **Symptom:** story 6's rationale — "so the package cannot emit a frame its own
  readers reject" — is not achieved: the padded 5-octet body is still rejected
  by the AVP readers, and the tests route it only through header-only
  `DiameterDecap`.
- **Evidence:** the padded frame through `DiameterPushAVP` prints
  `AVP length below its header`; through `DiameterPopAVP` the same. A body that
  is a valid AVP sequence is already 4-aligned, so padding only repairs the
  header rule.
- **Fix:** state the limit on the Encap page and in the README, and add a config
  that pins the drop.
- **Capability:** CAP-3.

## V-9 — The End-to-End 12/20 prose misstates RFC 6733 (low)

- **Where:** `src/diameter.hh:36-40`; `src/diameterencap.hh:29-31`;
  `src/diameterratedsource.hh:33-35`; `README.md:311-313`.
- **Symptom:** the text describes an "epoch" in the high 12 bits that "advances
  when the low-order 20 bits wrap". RFC 6733 §3 says only: "Upon reboot,
  implementations MAY set the high order 12 bits to contain the low order 12
  bits of current time, and the low order 20 bits to a random value."
- **Evidence:** the RFC text; the code increments a 32-bit counter, so the low
  20 bits are message counts and the high 12 a wrap count. Across-reboot
  uniqueness is explicitly out of scope.
- **Fix:** describe the counter and its 12/20 presentation, and state that the
  RFC's cross-reboot guarantee is not claimed.
- **Capability:** CAP-3.

## V-10 — Reader pages list the AVP reason before the flag reason (low)

- **Where:** `src/diameterpushavp.hh`, `src/diameterpopavp.hh`,
  `src/diameterpopstorepushavp.hh` drop-reason lists; `src/diameter.hh:411-419`
  vs `:464-490`.
- **Symptom:** the pages list "an AVP in it is malformed" before "the flags are
  illegal", but the header check tests the flags before the AVP walk.
- **Evidence:** a 28-octet request with E set and a zero-length AVP reports
  `the E bit is set on a request`.
- **Fix:** reorder the bullets to match the check order.
- **Capability:** CAP-3.

## V-11 — Stories 6 and 9 deny their own implementations (medium)

- **Where:** `stories/6-...md` and `stories/9-...md`, frontmatter and
  `## Auto Run Result`.
- **Symptom:** both are `status: 'done'` with no Review Triage Log, while the
  Auto Run Result says "Planning only … no source, test or documentation file
  was changed" and "no implementation was started"; the same commits add the
  code and the tests.
- **Evidence:** `6900c6f` adds the padding, alignment check, six configs and
  docs; `6fb37ae` (merge `39efb5e`) adds the counters and six tests. Reported
  suite totals never cover the tree: 103 at the base, 138 claimed, 146 in the
  commit, 149 at HEAD.
- **Fix:** fill in both records with the shipped change, a suite count measured
  at the tree, and a review triage.
- **Capability:** CAP-4.

## V-12 — The deferred ledger is self-contradictory and stale (low)

- **Where:** `_bmad-output/implementation-artifacts/deferred-work.md:1-53`.
- **Symptom:** the header says "Presently empty" above six open items; DW-3 and
  DW-4 end mid-sentence; every `location:` is stale.
- **Evidence:** DW-3 `hasUint` is at `:148` not `:108`; DW-4's Encap stamp at
  `:97` not `:63`; DW-6's `randString()` at `:40-68` not `:190-208`; DW-1
  points into `AvpHeader` rather than `decode()`.
- **Fix:** correct the header, finish the entries from the stories' `deferred:`
  frontmatter, and refresh the locations.
- **Capability:** CAP-4.

## V-13 — Three documentation sentences contradict the suite (low)

- **Where:** `README.md:223-226`; `tests/README.md:237-238`;
  `tests/smoke.bats:190-233` (helper comment).
- **Symptom:** the README names four of the fourteen refused configs; the tests
  README says every other config "prints bytes" although the overflow config
  prints a drop warning; the helper claims wall-clock detection its immediate
  rerun cannot provide.
- **Evidence:** the config inventory and the helper source.
- **Fix:** name the four refusal families; exclude the overflow and the new
  padding-drop config; correct the comment (the `randomness-*` tests carry the
  clock rejection).
- **Capability:** CAP-3.

## Not findings

- **Encap's padding decision.** `SPEC-diameter-rfc-conformance` CAP-2 fixes the
  5-octet → 28-octet frame; only the claim and the test coverage change.
- **The dead padded-bound branch** (`src/diameter.hh:480-482`). The alignment
  check makes it unreachable; it is kept as defence in depth with a comment.
- **Equal identifiers under two threads.** 800 000 frames under `-j 2` produced
  no equal pair, and per-field uniqueness (what CAP-4 needs) holds.
