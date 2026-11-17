---
title: 'Reject out-of-range Command Code and Length'
type: 'bugfix'
created: '2026-11-17'
status: 'done'
review_loop_iteration: 0
followup_review_recommended: false
baseline_revision: 'd1db4ab5ea2e8833726cd0346a984ad4dd4aebbc'
context: ['{project-root}/AGENTS.md']
warnings: ['oversized']
deferred:
  - summary: >-
      Two other writers of the three-octet message Length still truncate it:
      DiameterEncap stamps Length 20 + payload with no ceiling, and
      DiameterPopStorePushAVP adds an AVP's padded length with no ceiling.
    evidence: |-
      Measured against the installed package: a 16,777,200-octet payload into
      DiameterEncap produced a 16,777,220-octet frame declaring Length 0x000004,
      and two maximal DiameterPushAVP messages through DiameterPopStorePushAVP
      produced a 33,554,404-octet frame declaring Length 16,777,188. Both are
      pre-existing at d1db4ab, and the resolved intent names DiameterPushAVP for
      the Length half, so this story does not fix them. Closing them needs a
      run-time drop in each element, a config per element, and the same
      documentation sentence the PushAVP page now carries.
    location: >-
      src/diameterencap.cc:63, src/diameterpopstorepushavp.cc:85
    severity: medium
  - summary: >-
      DiameterAvpEncap truncates the three-octet AVP Length (RFC 6733 section
      4.1) for a value above 0xFFFFFF - 12.
    evidence: |-
      header.setLength(headerLength + valueLength) at src/diameteravpencap.cc:54
      is unguarded; a 16,777,210-octet payload emits an envelope whose Length
      field reads 000002. Pre-existing and a different field from the message
      Length this story guards, so it is deferred rather than patched. Closing it
      needs a run-time drop and a boundary config, following the PushAVP pattern.
    location: >-
      src/diameteravpencap.cc:54
    severity: medium
  - summary: >-
      A RAND*STRING count is unbounded and the value is materialised before the
      ceiling guard decides to drop, so an always-overflowing config pays its
      allocation and random draws on every packet.
    evidence: |-
      randString() at src/diameterpushavp.cc:190-208 builds the whole value, then
      the guard at :228 drops it; a count of 20,000,000 burns roughly 0.4 s and
      39 MB per packet, and a larger count fails to allocate. This is a
      pre-existing argument hazard: at d1db4ab the same count also allocated the
      value, then emitted a frame with a wrapped Length. The SPEC excludes
      performance work, and a configure-time cap would add argument surface the
      intent did not ask for. What would settle it: a configure-time rejection of
      counts that cannot fit even a 20-octet message, documented in the four
      RAND*STRING items.
    location: >-
      src/diameterpushavp.cc:190-233
    severity: low
---

<intent-contract>

## Intent

**Problem:** Both message writers truncate a Command Code that does not fit the three-octet field: `DiameterEncap(CODE 16777496, REQUEST true)` -- `0x01000118` -- configures cleanly and emits Command Code `0x000118`, with no error and no warning, and `DiameterRatedSource` shares the path because `DiameterHeader::setCode()` stores a `uint32_t` and `encode()` writes only its low three octets. The same silence hides an overflowing message: `DiameterPushAVP` appends without checking the three-octet Length field, so a large value wraps Length to `0x000000` on a 16,777,216-octet frame instead of being dropped (finding A-9, CAP-2).

**Approach:** Reject `CODE` above `0xFFFFFF` at configure time in both writers, with an error naming the argument and the field. In `DiameterPushAVP`, compute the length the append would produce and, when it exceeds `0xFFFFFF`, drop the packet with one warning instead of wrapping the field -- a run-time decision because the final length depends on the value.

## Boundaries & Constraints

**Always:** `CODE 0xFFFFFF` is accepted and written as `ffffff`; every accepted configuration keeps today's exact bytes; a rejected `CODE` fails configuration before any packet is produced; a message whose appended total is at most `0xFFFFFF` still appends; the overflow drop prints one warning naming the element and the reason and emits no packet; tabs for indentation; the package stays warning-free at `-Wall -Wextra`.

**Never:** No change to `DiameterHeader` encoding, `AvpHeader`, or any reader; no change to the AVP Length rule, value precedence, random draw order, or the `MANDATORY`/`VENDORSPEC` rules; no new argument; no rejection of `0xFFFFFE` or `0xFFFFFF`, which section 3.1 reserves for experimental use and which are in range; no message alignment or reader check, which is story 6's; no repair of a wrapped frame and no persistent state; no edit to `.github/workflows/`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Encap, CODE too large | `DiameterEncap(CODE 16777496, REQUEST true)` on `de ad be ef` | configure fails before any packet | error names `CODE`, `0xFFFFFF` and RFC 6733 section 3 |
| RatedSource, CODE too large | `DiameterRatedSource(CODE 16777496, REQUEST true, LIMIT 1, STOP true)` | configure fails before any packet | the same error from `DiameterRatedSource` |
| Largest legal CODE | `CODE 16777215` in either writer | 24-octet Encap frame / 20-octet message, code `ffffff` | No error expected |
| Length would overflow | 20-octet request then `DiameterPushAVP(CODE 264, RANDHEXSTRING 16777188)`: 20 + 16,777,196 = 16,777,216 | packet dropped, no `Print` line | `DiameterPushAVP: dropping packet: appending the AVP would exceed the three-octet Length field (RFC 6733 section 3)` |
| Largest legal message | the same append at `RANDHEXSTRING 16777184`: 16,777,212 octets | appended, Length `0xfffffc`, no drop | No error expected |
| Well-formed input | every existing `encap-*`, `rated-source*`, `push-avp*` and `rand-*` config | bytes unchanged | No error expected |

</intent-contract>

## Code Map

- `src/diameter.hh:13-16` -- the shared size enum; add `DIAMETER_MAX_24BIT_VALUE = 0xFFFFFF` with a comment naming the Command Code and Message Length fields, so the three writers share one named ceiling.
- `src/diameter.hh:65-67` -- `DiameterHeader::setCode()` stores any `uint32_t`; `:154-156` `encode()` writes the low three octets, which is the truncation the guard prevents from succeeding.
- `src/diameterencap.cc:15-52` -- `configure()`; `:24-32` the `Args` chain ending in `.complete()`, `:34-42` the flag refusals whose `errh->error(...)` style to follow. The CODE guard is a sibling after parsing; `<click/error.hh>` is already included.
- `src/diameterratedsource.cc:24-64` -- `configure()`; `:36-45` the `Args` chain, `:52-59` where `_code` and `dh` are filled. `<click/error.hh>` is already included. The guard text is identical to Encap's.
- `src/diameterpushavp.cc:170-241` -- `simple_action()`; `:172-179` the existing malformed-input drop via `diameter_check_message()`; `:213-217` where `messageLength`, `avpHeaderLength`, `avpDataLength`, `avpLength` and `avpLengthPadded` are computed; `:218` `p_in->put(avpLengthPadded)`; `:237` `dh.setLength(messageLength + header.getLengthPadded())`, the write the guard protects. `put()` is what prints Click's `expensive Packet::put` advisory, so a drop before it prints none.
- `src/diameterpushavp.cc:184-215` -- `valueString`/`valueUint` copies and `hasUint`: `String::length()` is an `int`, so with `messageLength <= 0xFFFFFF` the sum `messageLength + avpLengthPadded` cannot overflow `uint32_t`; no 64-bit arithmetic is needed.
- `src/diameterencap.hh:21-46` -- the `=d` paragraph and `=item CODE` where the range rule belongs; `src/diameterratedsource.hh:24-45` -- the same two places.
- `src/diameterpushavp.hh:34-40` -- the drop paragraph enumerating what the element refuses; `:73-75` `=item CODE` is the AVP Code, a four-octet field that keeps its range.
- `tests/smoke.bats:108-116` -- `expect_drop`, which hard-codes `dropping malformed packet:` and so cannot assert the overflow warning; `:121-135` `expect_configure_failure CONFIG ELEMENT MESSAGE`; `:367-405` `rand-hex-alphabet` shows the advisory-filtering shape a huge-append test needs; `:723-726` the Enc cap refusal test to copy; `:743-748` the RatedSource byte test.
- `tests/configs/encap-error-on-request.click` -- the four-octet payload and configure-failure shape; `tests/configs/rated-source.click` -- the RatedSource shape; `tests/configs/push-avp.click` -- the shared 20-octet request.
- `tests/README.md:171-191` -- the configure-path paragraph that counts ten refused configs; `:206` onward -- the config table; `:325-340` the drop-path and expectation paragraphs. `README.md:178-182` -- the element-reference rows for the two writers and PushAVP.
- `tests/manpages.bats:123-137` -- read-only: no argument is added, so the enumerated lists do not change.

## Tasks & Acceptance

**Execution:**
- `src/diameter.hh` -- add `DIAMETER_MAX_24BIT_VALUE = 0xFFFFFF` to the size enum with a comment naming both three-octet fields (RFC 6733 section 3) -- one named ceiling for the three guards.
- `src/diameterencap.cc` -- after `Args().complete()` succeeds and before the flag refusals, return `errh->error("the CODE argument must not exceed 0xFFFFFF: the Command Code field is three octets (RFC 6733 section 3)")` when `code > DIAMETER_MAX_24BIT_VALUE` -- a configure-time refusal instead of a silent truncation.
- `src/diameterratedsource.cc` -- the same guard with the same text after its `Args().complete()` and before `_code` is stored -- the second writer shares the defect.
- `src/diameterpushavp.cc` -- after `avpLengthPadded` is computed and before `p_in->put(...)`, drop with `click_chatter("%s: dropping packet: appending the AVP would exceed the three-octet Length field (RFC 6733 section 3)", class_name())` and `p_in->kill()` when `messageLength + avpLengthPadded > DIAMETER_MAX_24BIT_VALUE` -- the final length depends on the value, so this cannot be a configure check; the message is well formed, so the line must not claim malformed input.
- `src/diameterencap.hh`, `src/diameterratedsource.hh` -- state in `=d` that `CODE` must fit the three-octet Command Code field and that a larger value fails configuration, and add the range to `=item CODE` -- the man page is the only place a caller learns the limit.
- `src/diameterpushavp.hh` -- extend the drop paragraph: a message whose appended AVP would push the Length past three octets is dropped with its own warning, run time because the value decides the length -- distinguishes the new line from the malformed-input one.
- `tests/configs/encap-code-too-large.click`, `tests/configs/rated-source-code-too-large.click` -- `CODE 16777496` as a configure failure in each writer -- pins A-9's first half in both.
- `tests/configs/encap-code-max.click`, `tests/configs/rated-source-code-max.click` -- `CODE 16777215` emitting `ffffff` -- pins the threshold as inclusive, so an off-by-one guard that rejects `0xFFFFFF` fails.
- `tests/configs/push-avp-length-overflow.click` -- the 20-octet request into `DiameterPushAVP(CODE 264, RANDHEXSTRING 16777188)` -- pins the wrap as a drop.
- `tests/configs/push-avp-length-max.click` -- the same append at `RANDHEXSTRING 16777184`, printed with `MAXLENGTH 20` -- pins that the largest legal message (16,777,212 octets, Length `0xfffffc`) still appends, so the guard is not over-broad.
- `tests/smoke.bats` -- two `expect_configure_failure` tests, two code-max regex tests, one exact-warning test for the overflow (the output is a single line because the guard runs before `put()`), one regex test for the legal maximum that filters Click's `expensive Packet::put` advisory; extend the header comment to say which configs pin the Command Code range and the Length ceiling.
- `tests/README.md`, `README.md` -- count twelve refused configs and name the CODE range rule, add the six config-table rows, and describe the second drop shape beside the malformed one; extend the three element rows -- the indexes must not lag the suite.

**Acceptance Criteria:**
- Given the rebuilt package, when `CLICK=PREFIX/bin/click bats --tap tests` runs, then it exits 0 with every existing expectation unchanged.
- Given `CODE 16777496` to either writer, when Click configures it, then it exits non-zero with `the CODE argument must not exceed 0xFFFFFF: the Command Code field is three octets (RFC 6733 section 3)` and no packet reaches `Print`.
- Given `CODE 16777215`, when each writer emits, then the frame is 24 octets (Encap) or 20 octets (RatedSource) with Command Code `ffffff`.
- Given a 20-octet request and `RANDHEXSTRING 16777188`, when the frame would be 16,777,216 octets, then exactly the one warning `DiameterPushAVP: dropping packet: appending the AVP would exceed the three-octet Length field (RFC 6733 section 3)` is printed and nothing reaches `Print`.
- Given the same request at `RANDHEXSTRING 16777184`, when the element appends, then the frame is 16,777,212 octets with Length `0xfffffc` and no drop warning.
- Given the pre-change package at `d1db4ab`, when the six new configs run, then both `CODE 16777496` configs configure and print `... 80000118 ...`, the overflow config prints a 16,777,216-octet frame whose Length is `000000`, and the three boundary configs pass -- the negative control.

## Spec Change Log

## Review Triage Log

### 2026-11-17 — Review pass
- verdicts: 24 findings — high 0, medium 6, low 14, false 4, maybe-false 0
- note: the intent-alignment layer's item 8 recorded consistency, not a defect, so it is not counted; the blind hunter's third bullet carried two claims with different root causes (a pre-existing AVP-Length wrap and the new comment's wording), logged as two rows.
- findings:
  - `[medium]` `[defer]` `DiameterEncap` writes the message Length with no ceiling check (`src/diameterencap.cc:63`), so a 16,777,200-octet payload is stamped `Length 0x000004` on a 16,777,220-octet frame -- pre-existing and outside the intent, which names `DiameterPushAVP` for the Length half; recorded with the measured frame.
  - `[medium]` `[defer]` `DiameterPopStorePushAVP` performs the same unguarded append at `src/diameterpopstorepushavp.cc:85` -- pre-existing, not touched by this diff; measured: 33,554,404-octet frame declaring Length 16,777,188.
  - `[medium]` `[defer]` `DiameterAvpEncap` wraps the three-octet AVP Length (RFC 6733 section 4.1) for a 16,777,210-octet value (`src/diameteravpencap.cc:54`) -- a different field and a pre-existing defect; recorded for follow-up work.
  - `[low]` `[patch]` The new `DIAMETER_MAX_24BIT_VALUE` comment (`src/diameter.hh:16-19`) claimed "the writers refuse it or drop the packet", which the three unguarded sites above contradict -- patched: the comment now says a writer that would exceed the ceiling must refuse or drop, and names the three sites that enforce it.
  - `[low]` `[patch]` The man-page prose the diff adds (the `0xFFFFFF` limit on both writers, the overflow line on `DiameterPushAVP`) is asserted nowhere although `manpages.bats` already pins the sibling Version reason -- patched: the drop-path test now also requires `0xFFFFFF` on the two writer pages and the overflow reason on the PushAVP page.
  - `[low]` `[patch]` The CODE denial boundary is one-sided: `0x1000000`, the first illegal value, is never configured, so a guard lenient by up to the repro value passes every test -- patched with `encap-code-first-too-large.click` and `rated-source-code-first-too-large.click`.
  - `[low]` `[reject]` Drop precedence between malformed input and an overflowing append is undocumented and unpinned -- both outcomes drop the packet, the ordering is fixed by the existing validate-then-append structure, and a config cannot carry a malformed 16 MB literal to observe it; the prose fix would add surface for a cosmetic reason.
  - `[low]` `[patch]` `push-avp-length-max` prints only the 20-octet header, so the appended AVP at the ceiling (Length `0xffffe8`) is never asserted -- patched: `MAXLENGTH 36` and the AVP header is matched, which pins the padding arithmetic at the boundary.
  - `[low]` `[defer]` The ceiling guard runs after the value is materialised, so an always-overflowing `RAND*STRING` config allocates its value and burns its draws per packet before dropping -- pre-existing count hazard, unchanged in kind from `d1db4ab`, and the story excludes performance work; a configure-time cap would add argument surface the intent did not ask for.
  - `[low]` `[patch]` `README.md` dropped the specificity of "the two rejected `DiameterEncap` flag configs" and now reads as if only Encap and RatedSource refuse a configuration -- patched: the sentence names the refused families again.
  - `[low]` `[reject]` The story's `Always` line "every accepted configuration keeps today's exact bytes" contradicts a configuration that was accepted at `d1db4ab` and is now refused -- true as prose but the fix edits this build's spec, which this pass does not do; the behaviour change is intended and recorded in the Design Notes and Negative control.
  - `[low]` `[patch]` `README.md`'s row says the element "drops one whose appended Length would pass `0xFFFFFF`", where "pass" is ambiguous and the per-packet nature is missing -- patched: the row now says a packet whose appended AVP would push the Length past `0xFFFFFF` is dropped with its own warning.
  - `[low]` `[defer]` No bound or guidance exists on `RAND*STRING` counts, so a typo such as `167771888` allocates ~160 MB per packet -- pre-existing argument misuse, worsened only in that the oversized value is now dropped instead of corrupting a frame; documented ceiling interaction would be new surface.
  - `[low]` `[defer]` The value is fully generated before the guard decides to drop (`src/diameterpushavp.cc:190-233`), so an over-ceiling count pays its allocation and draws per packet -- same root cause and same deferral as the materialisation item above.
  - `[medium]` `[defer]` `DiameterPopStorePushAVP` still truncates the three-octet message Length -- pre-existing, verified with a 33,554,404-octet frame declaring Length 16,777,188; outside the intent's named element.
  - `[medium]` `[defer]` `DiameterEncap` still truncates for an inbound frame above `0xFFFFEB` -- pre-existing, verified with a 16,777,232-octet frame declaring Length `0x000010`; outside the intent's named element.
  - `[false]` `[reject]` The CODE half is observable only as diagnostic text and the truncation is asserted nowhere -- refuted: the configure gate is the fix, and removing or loosening it fails `encap-code-too-large` by configuring and printing a frame; the pre-fix bytes are recorded as the negative control in this spec.
  - `[low]` `[patch]` The deny-side boundary is unpinned relative to the accept side -- same root cause as the boundary row above; patched by the same two configs.
  - `[false]` `[reject]` The Length ceiling at exactly `0xFFFFFF` is unfalsifiable, so the predicate is unenforced -- refuted: every message Length this element emits is a multiple of 4 and `0xFFFFFF` is not, so no reachable frame can be mis-classified by either comparison; the reachable lattice is pinned at `0xFFFFFC` and `0x1000000`.
  - `[false]` `[reject]` The invariant is per-call-site, so a future writer or a direct `setCode()` would truncate silently -- refuted for the current tree: both writers are guarded and the only direct `setCode()` callers are those two; a hypothetical third writer is not a reachable bad outcome, and the existing unguarded Length writers are recorded as deferred items.
  - `[false]` `[reject]` Duplicating the guard text at two call sites will drift because nothing ties them -- refuted: each element's message is pinned by its own configure-failure test, so a divergence fails that test; no shared behaviour depends on the strings matching.
  - `[low]` `[defer]` The guard runs after value materialisation and makes an over-ceiling config pay for its value -- same root cause as the materialisation deferral above; no separate item.
  - `[low]` `[reject]` The new `DiameterRatedSource` block uses four-space indentation while its `return` uses a tab, against the story's tabs rule -- the block matches that file's established four-space statements; switching one block to tabs would be the inconsistent result, and the pre-existing style is not this story's to reformat.

## Design Notes

The two guards answer the same RFC 6733 section 3 sentence from opposite ends of the pipeline. `CODE` is configuration, so a value that cannot be encoded is a caller error and the element refuses to start; there is no legal interpretation of `0x01000118` as a three-octet type. The Length is different: `20 + 8 + value` is only known per packet, and a generator count is one way to reach it, so refusing the configuration would reject an element that emits valid frames for most values. The guard therefore sits in `simple_action()` and names the append rather than the input.

The overflow test generates its 16 MB value from `RANDHEXSTRING`, because no config literal can carry 16 MB and the generator's count states the intended value length directly. `RANDHEXSTRING 16777188` overflows: the AVP is 8 + 16,777,188 = 16,777,196 octets, already 4-aligned, so the message would be 16,777,216. `16777184` is the largest count that fits: 20 + 16,777,192 = 16,777,212 = `0xfffffc`, the largest multiple of 4 at or below the ceiling. Those two counts put a legal and an illegal frame one 4-octet step apart, so the pair pins both sides of `>`.

Verified baseline at `d1db4ab`, package installed in `/tmp/opencode/click-mt`:

```text
Encap  CODE 16777496:  01000018 80000118 00000000 161aea28 54fe3d85 deadbeef
Rated  CODE 16777496:  01000014 80000118 0000002a 189eefb7 57216345
Encap  CODE 16777215:  01000018 80ffffff 00000000 35ef5d15 14d96fa9 deadbeef
Rated  CODE 16777215:  01000014 80ffffff 0000002a 3bc12be7 3548255d
Push   RANDHEXSTRING 16777188: 16777216 octets, header 01000000 (Length wrapped)
Push   RANDHEXSTRING 16777184: 16777212 octets, header 01fffffc
```

The overflow run takes about 0.2 s and allocates 16 MB once, so the suite cost is acceptable; the legal-maximum test prints only the first 20 octets (`MAXLENGTH 20`) and ignores Click's advisory line, the same way `rand-hex-alphabet` does.

## Verification

**Commands:**
- `autoconf && ./configure --with-click=/tmp/opencode/click-mt --prefix=/tmp/opencode/click-mt && make CXXFLAGS="-g -O2 -Wall -Wextra -fPIC -shared" && make install` -- expected: builds with no warnings under `-Wall -Wextra`
- `CLICK=/tmp/opencode/click-mt/bin/click /tmp/opencode/bats-core/bin/bats --tap tests` -- expected: every test passes, including the six new ones
- `CLICK=/tmp/opencode/click-mt/bin/click /tmp/opencode/bats-core/bin/bats --tap --filter 'code|length' tests` -- expected: the six new configs pass together
- Negative control: install the package at `d1db4ab` into a second prefix and run the six new configs with `CLICKPATH=<second prefix>/lib` -- expected: both CODE-too-large configs configure and print a truncated `000118` frame, the overflow config prints a wrapped `01000000` header, and the three boundary configs pass
- Mutation checks: change `>` to `>=` in either CODE guard -- expected: that writer's code-max test fails; drop the push-avp guard -- expected: the overflow test fails on the wrapped frame; make the push-avp guard over-broad (`> DIAMETER_MAX_24BIT_VALUE - 4`) -- expected: `push-avp-length-max` fails on a dropped packet, since every message Length here is a multiple of 4 and `0xFFFFFF` is not, so no frame can equal the ceiling and `>` and `>=` are equivalent in that guard; restore and rerun green
- Installed pages: `man -M /tmp/opencode/click-mt/share/man DiameterEncap` (and `DiameterRatedSource`, `DiameterPushAVP`) -- expected: the three-octet limit is stated in the description and the `CODE` item, and the PushAVP page names the overflow drop

**Environment:** `/tmp/opencode/click-mt` is Click 2.1 built with `--enable-user-multithread` and already carries the story-7 package, so a plain `make install` overwrites it; `/tmp/opencode/bats-core/bin/bats` is bats-core 1.14.

## Auto Run Result

Status: done

**Change.** Both message writers now refuse a `CODE` above `0xFFFFFF` at configure time with `the CODE argument must not exceed 0xFFFFFF: the Command Code field is three octets (RFC 6733 section 3)`, instead of silently emitting the low three octets: `CODE 16777496` (`0x01000118`) used to go out as Command Code `0x000118`. `DiameterPushAVP` now computes the padded length its append would produce and, when `messageLength + avpLengthPadded` exceeds `0xFFFFFF`, drops the packet with its own warning before `put()`, so a 16,777,216-octet frame can no longer wrap Length to `0x000000`. The shared constant `DIAMETER_MAX_24BIT_VALUE` names the ceiling; `0xFFFFFE` and `0xFFFFFF` stay legal. Closes finding A-9 for CAP-2.

**Files changed.**
- `src/diameter.hh` -- `DIAMETER_MAX_24BIT_VALUE` and a comment naming the three sites that enforce it.
- `src/diameterencap.cc`, `src/diameterratedsource.cc` -- the configure-time `CODE` range refusal, placed after argument parsing and before the flag refusals / member fill.
- `src/diameterpushavp.cc` -- the run-time append ceiling drop with `DiameterPushAVP: dropping packet: appending the AVP would exceed the three-octet Length field (RFC 6733 section 3)`.
- `src/diameterencap.hh`, `src/diameterratedsource.hh` -- the range rule in `=d` and `=item CODE`.
- `src/diameterpushavp.hh` -- the drop paragraph distinguishes the well-formed overflow drop from the malformed-input drop.
- `tests/configs/encap-code-too-large.click`, `encap-code-first-too-large.click`, `encap-code-max.click`, `rated-source-code-too-large.click`, `rated-source-code-first-too-large.click`, `rated-source-code-max.click` -- the rejection repros, the first illegal value in both writers, and the inclusive ceiling.
- `tests/configs/push-avp-length-overflow.click`, `push-avp-length-max.click` -- the 16,777,216-octet drop and the 16,777,212-octet largest legal append.
- `tests/smoke.bats` -- eight tests over the new configs and the coverage comment.
- `tests/manpages.bats` -- the writer pages must state `0xFFFFFF` and the PushAVP page the overflow reason.
- `tests/README.md`, `README.md` -- fourteen refused configs, the CODE range rule, the new drop shape, the config-table rows and the element rows.

**Review.** One pass over four layers: 24 findings, high 0, medium 6, low 14, false 4. Five patched entries covering seven findings, all low: the over-broad shared-constant comment was scoped to the enforcing sites; the CODE denial boundary gained the first illegal value `0x1000000` in both writers; `manpages.bats` now asserts the new prose; `push-avp-length-max` prints 36 octets and pins the AVP at the ceiling (`00000108 00ffffe8`); and the two `README.md` sentences were corrected. Ten findings deferred as three items -- unguarded message Length in `DiameterEncap` and `DiameterPopStorePushAVP`, unguarded AVP Length in `DiameterAvpEncap`, and unbounded `RAND*STRING` counts materialised before the guard -- all pre-existing and outside the intent's named element. Seven rejected: four false (the CODE half being diagnostic-only, the exact-ceiling predicate being unfalsifiable on a 4-aligned lattice, a hypothetical future writer, and duplicated guard text drifting) and three low (malformed-vs-overflow reason precedence, the story's own `Always` wording whose fix would edit the spec, and one file's pre-existing four-space indentation).

**Follow-up review recommendation: false.** No high or medium entry was patched; every patched entry was low, so the pass converged.

**Verification.**
- `-Wall -Wextra`: full rebuild of all ten sources, zero compiler diagnostics (only autoconf's pre-existing `AC_OUTPUT` notice).
- `CLICK=/tmp/opencode/click-mt/bin/click bats --tap tests`: 138/138, exit 0, including the eight new config tests and the new man-page test.
- Negative control against the installed `d1db4ab` package in `/tmp/opencode/s8b-base-prefix`: the four CODE-range configs behave as the baseline did -- `CODE 16777496` configures and prints `... 80000118 ...` in both writers and `CODE 0xFFFFFF` prints `ffffff` -- while `push-avp-length-overflow` prints a 16,777,216-octet frame whose header is `01000000` (wrapped Length) and `push-avp-length-max` appends 16,777,212 octets.
- Mutation checks: `>` to `>=` in either CODE guard fails that writer's `code-max` test; deleting the PushAVP guard fails `push-avp-length-overflow`; an over-broad PushAVP guard fails `push-avp-length-max`. Restored and rerun green.
- Installed pages inspected: `DiameterEncap` and `DiameterRatedSource` state the `0xFFFFFF` limit in the description and the `CODE` item, and `DiameterPushAVP` names the overflow drop; `manpages.bats` now enforces all three.

**Residual risks.** The intent names `DiameterPushAVP` for the Length half, so `DiameterEncap` (inbound packets above `0xFFFFEB`) and `DiameterPopStorePushAVP` still wrap the three-octet message Length, and `DiameterAvpEncap` still wraps the AVP Length; `DiameterEncap`'s conformance claim in CAP-2 therefore remains partly open, recorded in `deferred`. The overflow guard runs after the value is materialised, so an always-overflowing `RAND*STRING` config pays its allocation per packet; that is a pre-existing argument hazard and the SPEC excludes performance work.
