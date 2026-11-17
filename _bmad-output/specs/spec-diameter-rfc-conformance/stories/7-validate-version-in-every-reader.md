---
title: 'Validate Version in every reader'
type: 'bugfix'
created: '2026-11-17'
status: 'done'
baseline_revision: '118e40e960e12ee5e49681bc430be756ac67bd43'
review_loop_iteration: 0
followup_review_recommended: false
context: ['{project-root}/AGENTS.md']
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** `diameter_check_header()` tests Length and the E/T flags and nothing else, so `02 00 00 14 80 00 01 18 …` (Version 2, declared Length 20) passes every reader; worse, every element that rewrites a message decodes the header, mutates flags or Length and re-encodes it, so the bogus Version is copied straight through and a malformed frame leaves the graph still malformed (finding A-5, CAP-3). RFC 6733 section 3 fixes Version at 1.

**Approach:** Add a bad-Version reason to the shared check and test `buffer[0] == 1` before the Length and flag checks, so `DiameterDecap`, `DiameterFlipRequest`, `DiameterPushAVP`, `DiameterPopAVP` and `DiameterPopStorePushAVP` all drop the frame with one warning instead of round-tripping it. `DiameterAvpDecap` is unchanged: an AVP has no Version field.

## Boundaries & Constraints

**Always:** The version test runs before the Length comparison and the flag tests, so a bad Version outranks a Length mismatch and a flag fault; a dropped frame produces one warning naming the element and the reason and no output packet; a well-formed Version 1 frame keeps its exact bytes and every existing expectation; tabs for indentation; the package stays warning-free at `-Wall -Wextra`.

**Never:** No change to any writer's output (`DiameterEncap` and `DiameterRatedSource` already emit Version 1 and expose no argument to change it); no new arguments; no message alignment or Command Code validation (stories 6 and 8); no change to `DiameterAvpDecap` or to the AVP checks; no repair or re-encoding of a bad frame.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| All four rewriters | The 20-octet Version 2 request `02 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02` into `DiameterPushAVP`, `DiameterPopAVP`, `DiameterPopStorePushAVP` and `DiameterFlipRequest` | each drops the packet; no `Print` line | `ELEMENT: dropping malformed packet: the Version field is not 1` |
| Header reader | The same frame into `DiameterDecap` | dropped, payload not forwarded | `DiameterDecap: dropping malformed packet: the Version field is not 1` |
| Precedence | A Version 2 frame whose Length field says 100 on 20 octets | dropped for the Version, not the Length | reason `the Version field is not 1` |
| Short frame | A 4-octet Version 1 packet | dropped as before, the existing reason | `packet shorter than the 20-octet Diameter header` |
| Well-formed input | Every existing `encap-*`, `push-avp*`, `pop-*`, `flip-*`, `avp-*` config | bytes unchanged | No error expected |

</intent-contract>

## Code Map

- `src/diameter.hh:278-289` -- the `DiameterCheck` enum; add `DIAMETER_CHECK_BAD_VERSION`. `:291-316` -- `diameter_check_reason()`; a new reason needs a case or it falls through to "unknown validation error".
- `src/diameter.hh:318-338` -- `diameter_check_header()`; `:323-324` the short-header guard, `:325-328` the Length comparison, `:332-336` the flag tests. The version test goes before the Length comparison but must not read `buffer[0]` on a zero-octet packet.
- `src/diameter.hh:381-407` -- `diameter_check_message()` calls `diameter_check_header()` first, so every message walker inherits the check without an edit.
- `src/diameterdecap.cc:16-24`, `src/diameterfliprequest.cc:16-24`, `src/diameterpopavp.cc:18-26`, `src/diameterpopstorepushavp.cc:46-54`, `src/diameterpushavp.cc:172-179` -- the five call sites; each already prints the shared reason and kills the packet.
- `src/diameterfliprequest.cc:27-28,44`, `src/diameterpopavp.cc:34-35,43`, `src/diameterpopstorepushavp.cc:56-57,76,82`, `src/diameterpushavp.cc:220-221,238` -- the decode/encode round trip that re-emits the received Version; the shared check is what stops it reaching these lines.
- `src/diameterencap.cc:56-58`, `src/diameterratedsource.cc:55` -- writers leave `DiameterHeader`'s `version(1)` default; no writer can emit Version 2.
- `src/diameterdecap.hh:27-49`, `src/diameterfliprequest.hh:105-111`, `src/diameterpopavp.hh:158-164`, `src/diameterpopstorepushavp.hh:220-226`, `src/diameterpushavp.hh:34-40` -- the enumerated drop reasons each page states; the version reason joins them.
- `src/diameteravpdecap.hh:33-52` -- read-only: an AVP carries no Version, so its list does not change.
- `tests/smoke.bats:18-43` -- the header comment naming what the `malformed-*` tests cover; `:100-110` `expect_drop`; `:781-922` the malformed tests.
- `tests/configs/malformed-error-on-request-length.click` -- the fault-plus-mismatch shape the Version precedence config copies; `tests/configs/malformed-avp-in-message-popstorepush-vendor-id-zero.click` -- the two-output wiring `DiameterPopStorePushAVP` needs.
- `tests/README.md:154-200` -- the drop-path paragraph and the config table; `README.md:235-242` -- the prose that says the message readers check "Length and flags".

## Tasks & Acceptance

**Execution:**
- `src/diameter.hh` -- add `DIAMETER_CHECK_BAD_VERSION`, its reason `"the Version field is not 1"`, and the test `if (length >= 1 && buffer[0] != 1) return DIAMETER_CHECK_BAD_VERSION;` placed before the short-header guard and the Length comparison -- RFC 6733 section 3 requires Version 1, and the `length >= 1` guard keeps a zero-octet packet from being read out of bounds.
- `src/diameterdecap.hh`, `src/diameterfliprequest.hh`, `src/diameterpopavp.hh`, `src/diameterpopstorepushavp.hh`, `src/diameterpushavp.hh` -- name the bad-Version drop beside the existing short-header and Length reasons -- the man page is where a caller learns what the reader refuses.
- `tests/configs/malformed-version-pushavp.click`, `...-popavp.click`, `...-popstorepush.click`, `...-flip-request.click` -- the 20-octet Version 2 request into each rewriter -- pins A-5 as a drop rather than a round trip.
- `tests/configs/malformed-version-decap.click` -- the same frame into `DiameterDecap` -- proves the plainest header reader drops it and forwards no payload.
- `tests/configs/malformed-version-length.click` -- the same first octet with Length 100 on 20 octets -- pins that the Version reason outranks the Length reason.
- `tests/smoke.bats` -- one `expect_drop` test per new config, and the header comment extended to say the malformed set covers a bad Version.
- `tests/README.md`, `README.md` -- the drop-path paragraphs and the config-table rows -- both currently say the message readers check Length and flags only.

**Acceptance Criteria:**
- Given the rebuilt package, when `CLICK=PREFIX/bin/click bats --tap tests` runs, then it exits 0 with every existing expectation unchanged.
- Given the 20-octet Version 2 frame, when each of `DiameterPushAVP`, `DiameterPopAVP`, `DiameterPopStorePushAVP` and `DiameterFlipRequest` sees it, then exactly one drop warning naming that element and `the Version field is not 1` is printed and no packet reaches `Print`.
- Given the same frame, when `DiameterDecap` sees it, then it is dropped with the same reason and no payload is forwarded.
- Given a Version 2 frame whose Length also disagrees with the packet, when a reader sees it, then the reported reason is the Version, not the Length.
- Given the pre-change package at `118e40e`, when the six new configs run, then all four rewriters and `DiameterDecap` forward the frame and the precedence config reports the Length reason -- the negative control.
- Given any committed `encap-*`, `push-avp*`, `pop-*`, `flip-*` or `avp-*` config, when it runs, then its bytes are unchanged.

## Spec Change Log

## Review Triage Log

### 2026-11-17 — Review pass
- verdicts: 24 findings — high 0, medium 0, low 18, false 6
- findings:
  - `[low]` `[patch]` `tests/README.md` scopes the Version rule to "received frames", which reads as if `DiameterAvpDecap` checked it — Patched: the paragraph now says "received messages" and names `DiameterAvpDecap` as exempt because an AVP has no Version field.
  - `[low]` `[patch]` The Version-over-short-header precedence is untested — Patched with `malformed-version-short.click` (3 octets `02 00 00`); group: boundary coverage of the new first-octet test.
  - `[low]` `[reject]` Precedence over AVP-level faults is untested and undocumented — The header check runs before the AVP walk by construction in `diameter_check_message()`, and a doubly-malformed frame's reason is cosmetic; no config can observe a harmful difference, so the extra surface is not worth adding.
  - `[false]` `[reject]` `findings.md:106` still says "checks Length and flags first" — `findings.md` is the baseline audit of `4a007de` and is deliberately left as pre-fix evidence; every earlier story shipped without rewriting it.
  - `[low]` `[reject]` `malformed-version-popstorepush` routes port 1 to `Discard`, so a stray second-output packet is unobservable — With `LIMIT 1` and an unarmed store, output 1 is unreachable by construction, and the drop precedes the store write in the same check; a two-packet variant adds surface without a named harm.
  - `[low]` `[reject]` `malformed-version-decap` is header-only, so "no payload forwarded" is vacuous — `expect_drop` asserts whole-transcript equality, so the baseline's `decap: 0` Print line already fails the test; the comment wording is loose but the test discriminates.
  - `[low]` `[patch]` The `length >= 1` guard has no test — Patched with `malformed-empty-packet.click` (`LENGTH 0`); group: boundary coverage of the new first-octet test.
  - `[low]` `[patch]` The `smoke.bats` coverage comment omits the zero-Vendor-Id reason — Patched: the enumeration now names it.
  - `[low]` `[reject]` The man pages never state the full precedence order — The drop lists already present reasons in check order, and `tests/README.md` states Version-vs-Length and Version-vs-short-header; repeating the chain on five pages is redundant surface.
  - `[low]` `[patch]` `manpages.bats` only greps the generic drop-path sentence — Patched: the test now requires `the Version field is not 1` in each of the five message readers' DESCRIPTION (whitespace-flattened).
  - `[false]` `[reject]` Inserting `DIAMETER_CHECK_BAD_VERSION` mid-enum renumbers existing constants — `diameter.hh` is not installed (`make install` ships only `diameter.uo`), the enum is never serialized, so no consumer can observe the values.
  - `[low]` `[reject]` `README.md`'s "the five that read a message" includes the header-only readers — Pre-existing wording the diff only extended by one noun; the sentence names all six elements and no behaviour follows from the phrasing.
  - `[low]` `[reject]` The spec's no-regression matrix row lists only some config families — The fix would edit the spec, and the acceptance criterion plus the full-suite run already cover every existing expectation.
  - `[low]` `[patch]` `diameter_check_header()`'s comment still promises a whole 20-octet header although the Version branch fires on one octet — Patched: the comment now states the Version-first test and the one-octet guard; group: stale function comments.
  - `[low]` `[patch]` The zero-octet boundary of the Version guard has no test (pre-verified) — Patched with `malformed-empty-packet.click` and its `expect_drop`; dropping the `length >= 1` clause now fails that test.
  - `[low]` `[reject]` The recorded negative-control command is a no-op without `CLICKPATH` (pre-verified) — Real, and the fix is a spec edit; the correct invocation with `CLICKPATH=<prefix>/lib` is now recorded in this spec's Verification section and the Auto Run Result.
  - `[low]` `[patch]` `diameter_check_message()`'s comment omits the Version condition — Patched with the comment group above.
  - `[false]` `[reject]` Intent surface is four elements while the change is one shared function — The story description names the shared header check; each of the four elements is verified by name to drop the frame.
  - `[false]` `[reject]` The tests pin a self-coined reason string and no committed test holds the pre-change bytes — The reason string is the package's established drop-reason surface, and committing pre-change bytes would pin the bug.
  - `[false]` `[reject]` `DiameterDecap` and the precedence config exceed the four-element sentence — CAP-3 requires every reader to drop an invalid frame, and the story description names the shared check; the four named elements are covered individually.
  - `[low]` `[patch]` The Version-vs-short-header boundary is unpinned — Patched with `malformed-version-short`; group: boundary coverage of the new first-octet test.
  - `[low]` `[patch]` The one-octet guard is untested — Patched with `malformed-empty-packet`; group: boundary coverage of the new first-octet test.
  - `[low]` `[patch]` The man-page surface is unverified — Patched by extending `manpages.bats` to require the new reason on the five message-reader pages.
  - `[false]` `[reject]` The story artifact is part of the diff — The spec is the workflow's required artifact and carries no behavioural claim of its own.

## Design Notes

Version is tested before the Length comparison because a frame that disagrees about the Version is not a Diameter message at any length: reporting its Length first would describe a field of a message the reader has already rejected. That ordering is why the check is guarded on `length >= 1` rather than moved after the 20-octet short-header guard -- the guard keeps the first-octet read safe without letting a Length or framing fault outrank the Version. A Version 1 short packet still reports `packet shorter than the 20-octet Diameter header`, which `malformed-short-packet` and `malformed-flip-request-short` already pin.

The 20-octet repro frame is a bare request: flags `80` (R), code `000118`, App-Id 0, hbh 1, e2e 2. Wrapped in the usual `Print(..., MAXLENGTH 200, CONTENTS HEX)` it currently prints a frame beginning `02000020` after `DiameterPushAVP` appends 12 octets, `02000014` after `DiameterPopAVP` finds no AVP, `02000014` with flags `00` after the flip, and `02000014` unchanged after the pop-store-push; on the fixed package each run prints only the one warning line.

Two configs pin the edges of the placement rather than the repro itself. `malformed-version-short` sends three octets starting `02`, so moving the Version test below the short-header guard changes its reason and fails; `malformed-empty-packet` sends `LENGTH 0`, so dropping the `length >= 1` guard reads past the buffer and fails too. Those are the only two behaviours the new ordering adds beyond the 20-octet frame, and a Version 1 short packet keeps the existing short-header reason, which `malformed-short-packet` already pins.

## Verification

**Commands:**
- `autoconf && ./configure --with-click=/tmp/opencode/click-mt --prefix=/tmp/opencode/click-mt && make CXXFLAGS="-g -O2 -Wall -Wextra -fPIC -shared" && make install` -- expected: builds with no warnings under `-Wall -Wextra`
- `/tmp/opencode/bats-core/bin/bats --tap tests` with `CLICK=/tmp/opencode/click-mt/bin/click` -- expected: every test passes, including the eight new ones
- `CLICK=/tmp/opencode/click-mt/bin/click /tmp/opencode/bats-core/bin/bats --tap --filter 'version|empty-packet' tests` -- expected: the eight new configs pass together
- Negative control: install the package at `118e40e` into a second prefix and run the six Version-frame tests with `CLICKPATH=<second prefix>/lib`, because a Click binary built with `--prefix` resolves the package from its own tree rather than from `CLICKPATH` alone -- expected: all six fail, five because the frame is forwarded and one because the Length reason is reported
- Mutation checks: delete the version test -- expected: all eight fail; move it after the Length comparison -- expected: `malformed-version-length` fails; move it below the short-header guard -- expected: `malformed-version-short` fails; drop the `length >= 1` guard -- expected: `malformed-empty-packet` fails; restore and rerun green
- `man -M /tmp/opencode/click-mt/share/man DiameterDecap` (and the four other reader pages) -- expected: the drop list names the bad Version

**Environment:** `/tmp/opencode/click-mt` is Click 2.1 built with `--enable-user-multithread` and already carries the story-5 package; `/tmp/opencode/bats-core/bin/bats` is bats-core 1.14.

## Auto Run Result

Status: done

**Change.** `diameter_check_header()` now rejects any message whose first octet is not 1, with the reason `the Version field is not 1`, and tests it before the short-header guard, the Length comparison and the flag tests. Because every message reader validates through that shared check, `DiameterDecap`, `DiameterFlipRequest`, `DiameterPushAVP`, `DiameterPopAVP` and `DiameterPopStorePushAVP` drop the 20-octet Version 2 frame instead of round-tripping it; no rewriting element can re-emit it. The test is guarded on `length >= 1` so a zero-octet packet is still reported as a short header rather than read out of bounds. Closes finding A-5 for CAP-3.

**Files changed.**
- `src/diameter.hh` -- `DIAMETER_CHECK_BAD_VERSION`, its reason, the Version-first test with the one-octet guard, and both header-check function comments updated.
- `src/diameterdecap.hh`, `src/diameterfliprequest.hh`, `src/diameterpopavp.hh`, `src/diameterpopstorepushavp.hh`, `src/diameterpushavp.hh` -- the drop lists and prose name the bad-Version reason.
- `tests/configs/malformed-version-decap.click`, `...-pushavp.click`, `...-popavp.click`, `...-popstorepush.click`, `...-flip-request.click` -- the 20-octet Version 2 frame into each reader.
- `tests/configs/malformed-version-length.click` -- Version 2 plus a Length mismatch: the Version reason wins.
- `tests/configs/malformed-version-short.click` -- a 3-octet `02 00 00`: the Version reason outranks the short-header reason.
- `tests/configs/malformed-empty-packet.click` -- a zero-octet packet: the one-octet guard reports the short header.
- `tests/smoke.bats` -- eight `expect_drop` tests and the coverage comment updated.
- `tests/manpages.bats` -- the drop-path test now requires the bad-Version reason on the five message-reader pages.
- `tests/README.md`, `README.md` -- the drop-path prose, the Version-vs-short-header and guard wording, and the config-table rows.

**Review.** One pass over four layers: 24 findings, high 0, medium 0, low 18, false 6. Five patched entries (11 findings, all low): the boundary coverage of the new first-octet test (adding `malformed-version-short` and `malformed-empty-packet`), both stale function comments, the man-page reason assertion, the `tests/README.md` "received messages" scope wording, and the `smoke.bats` reason enumeration. Nothing deferred. Thirteen rejected: six false (the baseline `findings.md`, the enum renumbering, and four descriptive intent-alignment observations about mechanism, test surface and the spec artifact) and seven low rejected as cosmetic, redundant surface, or a spec-edit fix.

**Follow-up review recommendation: false.** No high finding was patched; every patched entry was low, so the pass converged. Patched counts by verdict: high 0, medium 0, low 5 entries (11 findings), maybe-false 0.

**Verification.**
- `-Wall -Wextra`: clean build of all ten sources, zero compiler diagnostics.
- `CLICK=/tmp/opencode/click-mt/bin/click bats --tap tests`: 129/129, exit 0, no skips.
- `--filter 'version|empty-packet'`: the eight new tests pass.
- Negative control against an installed `118e40e` package with `CLICKPATH=/tmp/opencode/s7-base-prefix/lib`: the six Version-frame tests fail -- five forward the frame (`02000020`, `02000014`, `decap: 0`) and the precedence config reports `header Length does not match packet length`. The empty-packet test passes there by design, because the guard preserves the pre-existing short-header reason.
- Mutation checks: deleting the Version test fails all eight; moving it after the Length comparison fails `malformed-version-length`; moving it below the short-header guard fails `malformed-version-short`; removing the `length >= 1` guard fails `malformed-empty-packet`. The source was restored and the suite rerun green after each.
- Installed pages inspected, and `manpages.bats` now enforces it: all five message readers name `the Version field is not 1`.

**Residual risks.** The Version-first ordering changes the reported reason for a 1-to-19-octet frame whose first octet is not 1 from the short-header reason to the Version reason; both new edge configs pin that boundary, and a Version 1 short packet keeps the old reason. `DiameterAvpDecap` deliberately does not check a Version field, since an AVP has none.

