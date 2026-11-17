---
title: 'Enforce 4-octet message alignment on write and read'
type: 'bugfix'
created: '2026-11-17'
status: 'done'
baseline_revision: 'd1db4ab5ea2e8833726cd0346a984ad4dd4aebbc'
review_loop_iteration: 1
followup_review_recommended: false
context: ['{project-root}/AGENTS.md']
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** `DiameterEncap` stamps `Length = 20 + payload` with no padding, so `InfiniteSource(DATA \<de ad be ef 00>) -> DiameterEncap(CODE 280, REQUEST true)` emits a 25-octet frame whose Length field says 25. RFC 6733 section 3 requires the Message Length to be a multiple of 4, and the package's own message walkers then reject that frame as a short AVP. On the read side, `diameter_check_header()` compares Length to the packet and never tests alignment, so `DiameterDecap` and every rewriter accept and forward the same frame (finding A-4, CAP-2 and CAP-3).

**Approach:** `DiameterEncap` zero-pads the payload up to a 4-octet boundary and counts the padding in the message Length, mirroring the padding `DiameterAvpEncap` already applies to an AVP value. `diameter_check_header()` gains `DIAMETER_CHECK_LENGTH_NOT_ALIGNED` and rejects a declared Length that is not a multiple of 4, so every element that reads a message inherits the check and no rewriting element can re-emit an unaligned frame. The pad repairs the header rule only: a payload that is not already a sequence of padded AVPs is not made walkable, and `encap-padding-push-avp.click` pins that limit.

## Boundaries & Constraints

**Always:** A 5-octet payload yields a 28-octet frame with exactly three zero pad octets, Length `0x1c`; a 6-octet payload gets two pad octets and a 7-octet payload one; a payload already on the boundary (0, 4, 8 octets) gains no pad octet and keeps today's bytes; the pad octets are zero; the alignment test runs after the Version test and the 20-octet short-header guard, before the packet-length comparison, so the bad-Version reason still outranks it and the alignment reason outranks a Length mismatch; every existing aligned frame keeps its exact bytes and every existing expectation that does not carry an unaligned Length keeps its reason; per-packet state stays local in `simple_action()` as story 1 established; tabs for indentation; the package stays warning-free at `-Wall -Wextra`.

**Never:** No rejection of a non-aligned payload; padding is the mandated fix. No change to `DiameterHeader` or `AvpHeader` encoding, no change to `diameter_check_avp()`, no change to the AVP Length rule or its padding configs, and no new argument. No removal or weakening of the padded-bound guard in `diameter_check_message()`. No change to `DiameterRatedSource` (it emits a header-only 20-octet message), to `DiameterFlipRequest`'s rewrite, or to any writer's flags, Code, App-Id or identifiers. No three-octet Length-ceiling guard in `DiameterEncap`: that is story 8's deferred item and remains so. No edit to `.github/workflows/`, no persistent state, no repair of an incoming frame.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Three pad octets | `DATA \<de ad be ef 00>` into `DiameterEncap(CODE 280, REQUEST true)` | 28 octets, Length `0x1c`, payload `de ad be ef 00 00 00 00` | No error expected |
| Two pad octets | `DATA \<de ad be ef 00 11>` | 28 octets, Length `0x1c`, payload `de ad be ef 00 11 00 00` | No error expected |
| One pad octet | `DATA \<de ad be ef 00 11 22>` | 28 octets, Length `0x1c`, payload `de ad be ef 00 11 22 00` | No error expected |
| Already aligned | a 4-octet payload, or `LENGTH 0` | unchanged: 24 octets / 20 octets, no pad octet | No error expected |
| Header reader accepts the writer | `encap-padding.click` feeds the padded frame into `DiameterDecap` | forwarded as 8 octets, no drop line | No error expected |
| Padded body is not walkable | `encap-padding-push-avp.click` feeds the same padded frame into `DiameterPushAVP` | dropped, nothing appended: the pad does not form an AVP header | reason `AVP length below its header` |
| Unaligned declared Length | 25-octet frame, first bytes `01 00 00 19`, into `DiameterDecap` | dropped, no payload forwarded | `DiameterDecap: dropping malformed packet: the Length field is not a multiple of 4` |
| Unaligned rewriter | the same 25-octet frame into `DiameterPushAVP` | dropped, nothing appended | `DiameterPushAVP: dropping malformed packet: the Length field is not a multiple of 4` |
| Alignment beats mismatch | 24-octet frame whose Length field says 25 | dropped for the alignment, not the mismatch | reason `the Length field is not a multiple of 4` |
| Aligned mismatch | 24-octet frame whose Length field says 100 | unchanged reason `header Length does not match packet length` | existing `malformed-decap-length` expectation |
| Version beats alignment | a frame whose Version is 2 and Length is 25 | reason `the Version field is not 1`, not the alignment | `malformed-version-not-aligned.click` |
| Short header beats alignment | a 10-octet frame declaring 25 | reason `packet shorter than the 20-octet Diameter header` | `malformed-short-not-aligned.click` |

</intent-contract>

## Code Map

- Line numbers were taken at the planning baseline `d1db4ab`; the shipped tree
  moved them (`DiameterCheck` is at `src/diameter.hh:338-351`,
  `diameter_check_header()` at `:390-420`, `DiameterEncap::simple_action()` at
  `src/diameterencap.cc:76-112`). The symbols and the described placement are
  unchanged.

- `src/diameter.hh:284-296` -- the `DiameterCheck` enum; add `DIAMETER_CHECK_LENGTH_NOT_ALIGNED` immediately before `DIAMETER_CHECK_LENGTH_MISMATCH`, the order in which the checks run. `:298-325` -- `diameter_check_reason()`; a new case is required or the drop prints "unknown validation error".
- `src/diameter.hh:327-356` -- `diameter_check_header()`; `:339-340` the Version-first test, `:341-342` the short-header guard, `:343-344` the three-octet `declared` parse, `:345-346` the mismatch comparison, `:350-354` the flag tests. The alignment test goes between the parse and the comparison. `:393-404` -- `diameter_check_message()` calls `diameter_check_header()` first, so every message walker inherits the rule; `:415-417` is the padded-bound guard that becomes unreachable once the header requires alignment (keep it).
- `src/diameterencap.cc:63-78` -- `simple_action()`; `:69` the per-packet header copy, `:70-71` the two `click_random()` draws, `:72` the Length stamp, `:74` `push(20)`, `:75` `encode()`. Padding is computed from `p_in->length()` into locals between the copy and the push.
- `src/diameteravpencap.cc:48-63` -- the padding idiom to copy: `push(headerLength)`, then `put(paddingLength)` and a `memset` of the pad octets, then `encode()`. It also shows that `put()` in this pipeline prints no advisory (the `avp-padding-*` tests pass); a message pad must be zeroed the same way.
- `src/diameterencap.hh:23-27` -- the `=d` paragraph that currently says "the payload needs no padding"; `:37-40` the neighbouring CODE rule, whose tone to match. The new text is where a caller learns that Length is 20 plus a padded payload.
- `src/diameterdecap.hh:21-49`, `src/diameterfliprequest.hh:23-41`, `src/diameterpopavp.hh:18-32`, `src/diameterpopstorepushavp.hh:20-42`, `src/diameterpushavp.hh:29-40` -- the five message readers' drop prose; each enumerates the reasons in check order, so the alignment reason joins after the short-header one and before the mismatch. `src/diameteravpdecap.hh:26-52` -- read-only: a standalone AVP has no message header, so its list does not change.
- `tests/smoke.bats:32-35` -- the malformed-coverage header comment; `:111-118` `expect_drop ELEMENT REASON`; `:689-703` the encap byte test shape; `:712-731` `encap-decap` and `encap-push-pop`, the aligned frames that must not move; `:995-1003` the two malformed tests whose frames carry an unaligned Length.
- `tests/configs/malformed-avp-padding-overhang.click` -- a 30-octet frame declaring 30 whose AVP length 9 overhangs the padded bound; the alignment rule now fires first. `tests/configs/malformed-avp-trailing-octets.click` -- a 31-octet frame with three trailing octets; re-frame it to 32 octets with four trailing octets so it still reaches the AVP walk.
- `tests/configs/encap.click` and `encap-empty.click` -- the aligned and empty payload shapes the new padding configs copy, including the unseeded-identifier regex.
- `tests/README.md:154-170` -- the drop-path paragraph to extend with the alignment rule; `:172-190` -- the AVP-padding paragraph, whose message-level counterpart goes beside it; `:193-215` -- the refused-config count, unchanged; `:219-340` -- the config table that must gain every new row and the two changed rows; `:380-400` -- the expectation prose about padding and reason precedence.
- `README.md:180-187` -- the element-reference rows; `:243-253` -- the malformed-reader paragraph and the AVP-padding paragraph, both of which describe framing without the message rule.
- `tests/manpages.bats:157-182` -- the six-reader drop-path test, which already requires the bad-Version reason on the five message pages; the alignment reason joins that assertion. `:184-203` -- the writer pages test, where the Encap padding sentence can be asserted.
- `_bmad-output/specs/spec-diameter-rfc-conformance/findings.md:36-43` -- A-4's evidence, including that padding is the RFC-consistent half of the choice; `:99-118` -- the verified-correct list, whose padded-bound walk must keep working for aligned frames.

## Tasks & Acceptance

**Execution:**
- `src/diameter.hh` -- add `DIAMETER_CHECK_LENGTH_NOT_ALIGNED` and its reason `"the Length field is not a multiple of 4"`, then, after the `declared` parse and before the mismatch comparison, return it when `(declared & 3u) != 0` -- RFC 6733 section 3 makes the Length a multiple of 4 by construction, and the placement keeps the Version reason first and makes the alignment reason outrank a mismatch. Update both function comments to say "a multiple of 4".
- `src/diameterencap.cc` -- compute `payloadLength`, `paddedLength = (payloadLength + 3) & ~3u` and `paddingLength` from `p_in->length()`, stamp `Length = DIAMETER_MESSAGE_HEADER_LENGTH + paddedLength`, and after `push(DIAMETER_MESSAGE_HEADER_LENGTH)` append the pad with `put(paddingLength)` and zero it with `memset` -- the frame this element emits must satisfy the reader check added above, and the arithmetic is the message-level twin of `AvpHeader::getLengthPadded()`.
- `src/diameterencap.hh` -- replace the "payload needs no padding" sentence with the zero-pad rule: Length is 20 plus the padded payload, the pad is part of the message and therefore part of what `DiameterDecap` forwards, and the Message Length multiple-of-4 rule comes from RFC 6733 section 3.
- `src/diameterdecap.hh`, `src/diameterfliprequest.hh`, `src/diameterpopavp.hh`, `src/diameterpopstorepushavp.hh`, `src/diameterpushavp.hh` -- add "its Length field is not a multiple of 4" to each drop list/prose in check order -- the man page is where a caller learns what the reader refuses.
- `tests/configs/encap-padding.click` -- the 5-octet payload `de ad be ef 00` into `DiameterEncap(CODE 280, REQUEST true)`, printed, then into `DiameterDecap` and printed again -- pins the 28-octet frame, Length `0x1c`, three zero pad octets, and that the package's own reader accepts it.
- `tests/configs/encap-padding-two.click`, `tests/configs/encap-padding-one.click` -- a 6-octet and a 7-octet payload -- pin two and one pad octets so the padding formula is exercised at every residue, with the 4-octet and empty cases already pinned by `encap.click` and `encap-empty.click`.
- `tests/configs/malformed-length-not-aligned.click` -- a 25-octet frame `01 00 00 19 ... de ad be ef 00` into `DiameterDecap` -- pins the A-4 reader half and the exact frame the old `DiameterEncap` emitted.
- `tests/configs/malformed-length-not-aligned-pushavp.click` -- the same frame into `DiameterPushAVP(CODE 264, OCTETSTRING "x")` -- pins that a rewriter drops it instead of appending to it.
- `tests/configs/malformed-length-not-aligned-mismatch.click` -- a 24-octet frame whose Length field says 25 -- pins that the alignment reason outranks the mismatch reason.
- `tests/configs/malformed-version-not-aligned.click` -- a 25-octet frame starting `02 00 00 19` -- pins that the alignment test sits after the Version test, so a Version 2 frame still reports the Version.
- `tests/configs/malformed-short-not-aligned.click` -- a 10-octet frame `01 00 00 19 ...` declaring 25 -- pins that the short-header guard outranks the alignment test, which is also what keeps the three-octet parse from reading past a short packet.
- `tests/configs/malformed-avp-trailing-octets.click` -- change the frame to 32 octets with four trailing octets after the 8-octet AVP (`... 00 00 01 08 00 00 00 08 00 00 00 00`) -- keeps the partial-trailing-header coverage reachable under the new alignment rule without changing its reason.
- `tests/configs/malformed-avp-padding-overhang.click` -- keep the 30-octet frame and rewrite the banner comment -- the frame is now dropped by the header's alignment rule before the AVP walk, so the config pins the ordering and the new reason instead of the unreachable padded bound.
- `tests/smoke.bats` -- add one test per new config (`encap-padding`, `encap-padding-one`, `encap-padding-two`, `malformed-length-not-aligned`, `malformed-length-not-aligned-pushavp`, `malformed-length-not-aligned-mismatch`, `malformed-version-not-aligned`, `malformed-short-not-aligned`), update the two affected malformed tests and the malformed-coverage header comment -- the comment is the index of what the drop tests prove.
- `tests/manpages.bats` -- require `not a multiple of 4` in the DESCRIPTION of the five message readers, and require the Encap page to state the padding rule -- the pages are generated from the headers, so this catches a doc-only regression.
- `tests/README.md`, `README.md` -- add the alignment rule to the drop-path paragraph, the message-padding counterpart to the AVP-padding paragraph, the eight config-table rows, the Encap element row's padding, and the two changed rows -- the indexes must not lag the suite.

**Acceptance Criteria:**
- Given the rebuilt package, when `CLICK=PREFIX/bin/click bats --tap tests` runs, then it exits 0, including every existing expectation that does not involve an unaligned Length.
- Given a 5-octet payload, when `DiameterEncap` sees it, then the frame is 28 octets with three zero pad octets after the payload and Length `0x1c`, and `DiameterDecap` forwards its 8 payload octets without a drop.
- Given 6- and 7-octet payloads, when `DiameterEncap` sees them, then the frames are 28 octets with two and one zero pad octets and Length `0x1c`.
- Given a payload already on the 4-octet boundary, when `DiameterEncap` sees it, then no pad octet is added and the existing `encap`, `encap-empty`, `encap-decap`, `encap-push-pop` and `smp-encap` bytes are unchanged.
- Given the 25-octet frame whose Length says 25, when `DiameterDecap` or `DiameterPushAVP` sees it, then it is dropped with exactly one line `ELEMENT: dropping malformed packet: the Length field is not a multiple of 4` and nothing reaches `Print`.
- Given a 24-octet frame whose Length says 25, when a reader sees it, then the reported reason is the alignment, not the mismatch.
- Given a 10-octet frame declaring 25, when a reader sees it, then the reported reason is the short header, not the alignment; given a Version 2 frame declaring 25, then the reported reason is the Version.
- Given the pre-change package at `d1db4ab`, when the six configs whose behaviour changes run, then the three `encap-padding*` configs print 25-, 26- and 27-octet frames with unaligned Lengths, and the three `malformed-length-not-aligned*` configs forward the frame instead of dropping it -- the negative control. Given the same package, `encap-padding-push-avp` reports the short AVP header rather than the padded body's below-header length.
- Given the installed prefix, when the five message-reader pages are inspected, then each names `the Length field is not a multiple of 4` and the `DiameterEncap` page states the zero padding.

## Spec Change Log

## Review Triage Log

### 2026-11-17 — Verification review of stories 3-9

The shipped alignment rule and padding were reviewed against the tree on
`spec/diameter-rfc-conformance` (adversarial, edge-case and verification-gap
lenses; findings V-1 through V-13 in
`_bmad-output/specs/spec-diameter-conformance-verification/findings.md`).
Story 6's entries:

- `[patched]` The rationale "so the package cannot emit a frame its own readers reject" was false for the repro: the padded 5-octet body still fails the AVP walk with `AVP length below its header`, and only the header reader accepts it. Added `encap-padding-push-avp.click`, the Encap-page limit and the README sentence; the padding decision itself is unchanged because `SPEC-diameter-rfc-conformance` CAP-2 fixes it.
- `[patched]` The new `put()` (and the existing `push()`) on the padding path dereferenced null on allocation failure; both now return 0.
- `[patched]` The record said "no implementation was started"; this record replaces it with the suite count at the shipped tree.
- `[patched]` The recorded `(payloadLength + 4) & ~3u` mutation is identical to the real formula for residues 1-3 and could never fail the padding configs; replaced with `(payloadLength + 2) & ~3u`.
- `[rejected]` The padded-bound guard is unreachable once the header requires an aligned Length. It stays as defence in depth with a comment, which is what this story's `Never` requires.
- `[rejected]` The negative control cited `ec0b5f0`, which is not on the branch; the equivalent pre-change tree is `d1db4ab` (installed in `/tmp/opencode/s8b-base-prefix`), and its measured output matches the expected 25/26/27-octet frames.

## Design Notes

Padding is mandated over rejection for two reasons. RFC 6733 section 3 defines Length as covering "the padded AVPs", and section 4 says a number of zero-valued bytes are added to the end of an AVP's value, so a pad is the conformant way to reach the boundary; and the SPEC's constraint that existing `.click` configurations keep working favours a writer that repairs its own framing over one that refuses a legal packet. It also matches `DiameterAvpEncap`, which has padded since the hardening epic, so the package stops having two alignment policies.

The writer arithmetic is `paddedLength = (payloadLength + 3) & ~3u`; `paddingLength = paddedLength - payloadLength`, then `put(paddingLength)` and `memset` mirror `DiameterAvpEncap::simple_action()`. The pad is part of the message, so `DiameterDecap` forwards it with the payload: a stateless decapsulator has no record of the original unpadded length, and that is exactly what the RFC means by padding the message. The new config prints both halves so the behaviour is pinned rather than implied.

Alignment is tested before the packet-length comparison, for the same reason the Version is tested first: a Length field that is not a multiple of 4 cannot describe a Diameter message at any packet length, so comparing it to the packet would report a field of a message the reader has already rejected. It stays below the short-header guard, which both keeps the three-octet parse from reading past a short packet and makes a short frame report the short-header reason; `malformed-short-not-aligned.click` pins that side of the ordering. An aligned frame whose Length disagrees with the packet keeps `header Length does not match packet length`, which `malformed-decap-length` and `malformed-length-short` already pin.

Consequence worth recording: once the header guarantees a 4-multiple and the walk advances by padded lengths, `paddedLength > length - offset` in `diameter_check_message()` can no longer be true, because both sides are 4-multiples and the AVP Length is at most the remaining octets. The padded-bound guard therefore becomes defence in depth rather than a reachable branch; it stays, per the story's scope, and `malformed-avp-padding-overhang.click` now pins the header rule that outranks it. `malformed-avp-trailing-octets.click` is re-framed to 32 octets so the reachable partial-header branch keeps its own test.

The three-octet Length ceiling in `DiameterEncap` is still unguarded (story 8 recorded it as deferred); padding does not change that class of defect, since a payload one octet below the ceiling can now cross it by up to three octets. That stays deferred rather than being smuggled into this story.

## Verification

**Commands:**
- `autoconf && ./configure --with-click=/tmp/opencode/click-mt --prefix=/tmp/opencode/click-mt && make CXXFLAGS="-g -O2 -Wall -Wextra -fPIC -shared" && make install` -- expected: builds with no warnings under `-Wall -Wextra`
- `CLICK=/tmp/opencode/click-mt/bin/click /tmp/opencode/bats-core/bin/bats --tap tests` -- expected: every test passes, including the nine new ones
- `CLICK=/tmp/opencode/click-mt/bin/click /tmp/opencode/bats-core/bin/bats --tap --filter 'padding|not-aligned' tests` -- expected: the new and changed configs pass together
- Negative control: install the package at `d1db4ab` into a second prefix and run the six configs whose behaviour changes with `CLICKPATH=<second prefix>/lib`, because a Click binary built with `--prefix` resolves the package from its own tree rather than from `CLICKPATH` alone -- expected: the padding configs print 25, 26 and 27 octets with Lengths `000019`, `00001a` and `00001b`, and the three `malformed-length-not-aligned*` configs forward frames or drop for another reason instead
- Mutation checks: delete the alignment test -- expected: the three `malformed-length-not-aligned*` configs and `malformed-avp-padding-overhang` fail; move it after the mismatch comparison -- expected: `malformed-length-not-aligned-mismatch` fails; hoist it above the short-header guard -- expected: `malformed-short-not-aligned` fails; change the padding formula to `(payloadLength + 2) & ~3u` or to truncation -- expected: the `encap-padding*` configs fail on length (note `(payloadLength + 4) & ~3u` is identical for residues 1-3 and only fails an aligned payload, so it is not a discriminating mutation); drop the `memset` -- expected: the pad octets are not zero and the configs fail; restore and rerun green
- `man -M /tmp/opencode/click-mt/share/man DiameterEncap` (and the five reader pages) -- expected: the padding rule and the alignment reason are present

**Environment:** `/tmp/opencode/click-mt` is Click 2.1 built with `--enable-user-multithread` and already carries the story-8 package; `/tmp/opencode/bats-core/bin/bats` is bats-core 1.14.

## Auto Run Result

Status: done

**Change.** `DiameterEncap` zero-pads the payload to a 4-octet boundary and counts the pad in the Message Length; `diameter_check_header()` rejects a declared Length that is not a multiple of 4, so every message reader inherits the alignment rule and no rewriter can re-emit an unaligned frame. The pad repairs the header rule only: a body that is not already a sequence of padded AVPs is still dropped by the AVP readers, and `encap-padding-push-avp.click` pins that limit.

**Files changed.**
- `src/diameter.hh` -- `DIAMETER_CHECK_LENGTH_NOT_ALIGNED`, its reason, the alignment test between the Length parse and the mismatch comparison, and the two function comments.
- `src/diameterencap.cc` -- the pad arithmetic, `put()` and `memset`, and the null checks on `push()`/`put()`.
- `src/diameterencap.hh`, `src/diameterdecap.hh`, `src/diameterfliprequest.hh`, `src/diameterpopavp.hh`, `src/diameterpopstorepushavp.hh`, `src/diameterpushavp.hh` -- the padding rule and the alignment reason in each drop list, in check order.
- `tests/configs/encap-padding*.click` (three residues plus the padded-body drop), `malformed-length-not-aligned*.click` (three orderings), `malformed-version-not-aligned.click`, `malformed-short-not-aligned.click`, and the re-framed `malformed-avp-trailing-octets.click` / re-commented `malformed-avp-padding-overhang.click`.
- `tests/smoke.bats`, `tests/manpages.bats`, `tests/README.md`, `README.md` -- the tests, the page assertions and the indexes.

**Verification (at this tree).**
- `-Wall -Wextra`: clean build, no diagnostics.
- `CLICK=/tmp/opencode/click-mt/bin/click bats --tap tests`: 152/152, exit 0.
- The eight story-6 tests and `encap-padding-push-avp` pass together.
- Negative control against the `d1db4ab` package in `/tmp/opencode/s8b-base-prefix/lib`: `encap-padding`/`-two`/`-one` print 25/26/27 octets with Lengths `000019`/`00001a`/`00001b`; `malformed-length-not-aligned` forwards `deadbeef 00`; `-pushavp` drops with `packet shorter than the 8-octet AVP header`; `-mismatch` drops with `header Length does not match packet length`.
- On the shipped tree the padded frame through `DiameterPushAVP` drops with `AVP length below its header`, while `DiameterDecap` forwards the 8 padded octets.
- Installed pages carry the padding rule and the alignment reason, and `tests/manpages.bats` enforces them.

**Residual risks.** The padded-body limitation is documented and pinned rather than repaired: making an arbitrary payload walkable is outside this story. The three-octet Length ceiling in `DiameterEncap` remains deferred (DW-4).
