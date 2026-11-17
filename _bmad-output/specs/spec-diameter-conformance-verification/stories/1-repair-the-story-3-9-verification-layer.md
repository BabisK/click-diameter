---
title: 'Repair the story 3-9 verification layer'
type: 'bugfix'
created: '2026-11-17'
status: 'done'
baseline_revision: '39efb5ed61a871723ed2aa49888e094093f1d7ef'
review_loop_iteration: 1
followup_review_recommended: false
context: ['{project-root}/AGENTS.md']
warnings: []
deferred: []
---

<intent-contract>

## Intent

**Problem:** stories 3–9 ship code whose verification layer misreports it.
Stories 6 and 9 are `done` while their own record says no implementation was
started; the identifier test's equal-pair check compares numbers, so it can
report 377 false matches; the claims that the padded Encap frame is walkable and
that the baseline produced 37/30 equal identifiers are false; the seeded first
frame and the advance-on-emission counters are unpinned; three buffer extensions
are dereferenced unchecked; and the End-to-End, drop-order and refusal-inventory
prose contradict the code. Findings V-1 through V-13 in `findings.md` carry the
evidence.

**Approach:** repair the tests first so they measure identifiers, then harden the
three `push()`/`put()` sites, then correct the claims and the two story records
and the deferred ledger. One pull request on the current branch.

## Boundaries & Constraints

**Always:** keep `click_random()` as the identifier source; a literal pin is the
RNG's output for `RandomSeed(SEED 12345)`. Keep the wire format and Encap's
padding behaviour. Keep the man-page phrases `seeded once from click_random()`
and `unique for the first 2^32 messages of a run`. Tabs for indentation;
warning-free at `-Wall -Wextra`; the full suite green.

**Never:** no new element, argument, RNG or CI job; no change to the
`encap-padding*` bytes; no fix for DW-4, DW-5 or DW-6; no rewrite of the
rfc-conformance capabilities beyond the success-signal exception; no new branch.

## Tasks & Acceptance

**Execution:**
- `tests/smoke.bats` -- string comparison at the equal-pair check; a
  consecutiveness assertion from the first and last value plus the count and
  distinctness; a first-frame pin for `randomness-encap` and
  `randomness-rated-source`; split the helper so the wrap config can run once.
- `tests/configs/identifiers-encap-wrap.click` -- `LIMIT 1048577`, proving the
  2^20 carry.
- `tests/configs/randomness-encap-push-avp.click` -- a seeded writer chained to a
  `RAND*` generator, pinning the stream position.
- `tests/configs/encap-padding-push-avp.click` -- the padded body dropped by an
  AVP reader, pinning the limitation.
- `src/diameterencap.cc`, `src/diameterpushavp.cc`, `src/diameteravpencap.cc` --
  null checks after `push()`/`put()`.
- `src/diameter.hh` -- End-to-End counter wording; a comment on the unreachable
  padded-bound guard.
- `src/diameterencap.hh`, `src/diameterratedsource.hh` -- End-to-End wording; the
  Encap page gains the padding limitation.
- `src/diameterpushavp.hh`, `src/diameterpopavp.hh`,
  `src/diameterpopstorepushavp.hh` -- flag bullet before the AVP bullet.
- `README.md` -- End-to-End wording, the stream-position exception, the four
  refusal families, the padding limitation.
- `tests/README.md` -- the corrected baseline numbers, the consecutiveness
  wording, the "prints bytes" sentence, and rows for the three new configs.
- `stories/6-...md`, `stories/9-...md` -- implementation record, measured suite
  count and review triage; story 9's 37/30 numbers corrected.
- `_bmad-output/implementation-artifacts/deferred-work.md` -- header, truncated
  entries and locations.
- `SPEC.md` (rfc-conformance) -- the success-signal exception for the moved
  identifier draws.

**Acceptance Criteria:**
- Given the built package, when the full suite runs, then it exits 0 and the
  three new configs pass.
- Given the advance-on-refusal mutant, when the suite runs, then the
  consecutiveness assertion fails.
- Given the seed+1 mutant, when the suite runs, then the first-frame pin fails.
- Given the pre-change package, when the identifier tests run, then the
  first-frame and consecutiveness assertions fail as expected.
- Given the built package on a 1 048 577-message run, then both identifier
  fields are distinct, consecutive, and carry at 2^20.
- Given a padded 5-octet Encap frame through an AVP reader, then it is dropped
  with `AVP length below its header`, and the Encap page says so.

## Review Triage Log

### 2026-11-17 — Verification review of stories 3-9

- verdicts: 13 findings (V-1 through V-13): 12 patched, 1 rejected below.
- `[patched]` V-1: the identifier helper's equal-pair check compared hex fields numerically; now a string comparison. Verified: `SEED 10` reports 377 false matches before the fix and 0 after; the pre-change stream's 37/30 are 0/0 as strings.
- `[patched]` V-2: story 9's 37/30 baseline numbers corrected to 0/0, with the duplicate counts kept as the real defect.
- `[patched]` V-3: `randomness-encap` and `randomness-rated-source` pin the literal first frame; the seed+1 mutant fails them.
- `[patched]` V-4: the helper requires consecutive fields (distinct count + frame count + span); the advance-on-refusal mutant fails with `hop-by-hop values are not consecutive: 16d5a847 to 16dcfb3b over 240000 frames`.
- `[patched]` V-5: `identifiers-encap-wrap.click` crosses the 2^20 carry in 1 048 577 messages, 4.6 s.
- `[patched]` V-6: the mixed-config stream shift is documented in the README and the SPEC success signal, and pinned by `randomness-encap-push-avp.click`.
- `[patched]` V-7: null checks after `push()`/`put()` in `DiameterEncap`, `DiameterPushAVP` and `DiameterAvpEncap`.
- `[patched]` V-8: the Encap page and README state that padding repairs the header rule only; `encap-padding-push-avp.click` pins the drop.
- `[patched]` V-9: the End-to-End text describes a counter with a 12/20 presentation instead of the RFC's optional reboot-time split.
- `[patched]` V-10: the three reader pages list the flag reason before the AVP reason.
- `[patched]` V-11: stories 6 and 9 carry implementation records, measured suite counts and review triage; their baseline revisions point at the commits that actually carry their code.
- `[patched]` V-12: the deferred ledger header, the two truncated entries and every location.
- `[patched]` V-13: the README refusal inventory, the tests README "prints bytes" sentence and the helper's wall-clock comment.
- `[rejected]` The padding decision, the dead padded-bound branch and the multi-thread equal-pair concern are not defects: the first is pinned by `SPEC-diameter-rfc-conformance` CAP-2, the second is required defence in depth, and 800 000 frames under `-j 2` produced no equal pair.

## Design Notes

The consecutiveness proof avoids a per-frame hex parser: with `COUNT` frames,
`COUNT` distinct values and `last - first == COUNT - 1` (mod 2^32), the sequence
must be exactly consecutive. Bash's `16#...` arithmetic fits 32 bits.

## Verification

**Commands:**
- `autoconf && ./configure --with-click=/tmp/opencode/click-mt --prefix=/tmp/opencode/review/prefix && make CXXFLAGS="-g -O2 -Wall -Wextra -fPIC -shared" && make install`
- `CLICKPATH=/tmp/opencode/review/pkg2 CLICK=/tmp/opencode/click-mt/bin/click /tmp/opencode/bats-core/bin/bats --tap tests`

## Auto Run Result

Status: done

**Change.** The verification layer of stories 3-9 now measures what it claims: the identifier helper compares strings, requires consecutive fields, pins the seeded first frame and crosses the 2^20 carry; the three writer buffer extensions check for null; the Encap padding limit, End-to-End wording, drop-reason order and refusal inventory match the tree; and stories 6 and 9 plus the deferred ledger record the shipped code. No wire format changed; the only behaviour change is the allocation-failure drop.

**Files changed.**
- `tests/smoke.bats` -- string comparison, single-pass file-based identifier checks with the span proof, the first-frame argument, the wrap test, the mixed-config test, the padding-drop test, and the helper comments.
- `tests/configs/identifiers-encap-wrap.click`, `randomness-encap-push-avp.click`, `encap-padding-push-avp.click`.
- `src/diameterencap.cc`, `src/diameterpushavp.cc`, `src/diameteravpencap.cc` -- null checks.
- `src/diameter.hh`, `src/diameterencap.hh`, `src/diameterratedsource.hh`, `src/diameterpushavp.hh`, `src/diameterpopavp.hh`, `src/diameterpopstorepushavp.hh` -- the corrected prose and the defence-in-depth comment.
- `README.md`, `tests/README.md` -- the End-to-End counter, the stream-position exception, the padding limit, the refusal families, the corrected counts and the new rows.
- `_bmad-output/specs/spec-diameter-rfc-conformance/` -- the success-signal exception and the story 6/9 records.
- `_bmad-output/implementation-artifacts/deferred-work.md` -- the header, the truncated entries and the locations.

**Verification (at this tree).**
- `-Wall -Wextra`: clean build, no diagnostics.
- `CLICKPATH=/tmp/opencode/review/pkg2 CLICK=/tmp/opencode/click-mt/bin/click bats --tap tests`: 152/152, exit 0.
- The three new configs pass; the wrap test is 4.6 s and the two 240k tests are 1.6-1.8 s.
- Pre-change package (`/tmp/opencode/s8b-base-prefix/lib`): the three identifier tests fail on the duplicate counts, `encap-padding-push-avp` fails with the short-header reason, and the padding configs print 25/26/27 octets.
- Advance-on-refusal mutant: the consecutiveness assertion fails.
- Seed+1 mutant: the first-frame pin and the mixed config fail.
- Installed pages carry the new prose; `tests/manpages.bats` enforces it.
