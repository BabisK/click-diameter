---
title: 'Story 3: Pad AVP encoding to 4 octets'
type: 'bugfix'
created: '2026-11-16'
status: 'done'
review_loop_iteration: 0
followup_review_recommended: false
context: ['{project-root}/AGENTS.md']
warnings: []
deferred:
  - summary: >-
      `AGENTS.md` line 22 still says defect repros live in `tests/known-defects/`, which this story removes along with F-7's last repro.
    evidence: |-
      The line sits inside the bmad-project-context managed block, whose contents are replaced on refresh; triage defers findings whose fix edits an agent-context file. Refresh the block or wait for the context workflow.
    location: >-
      AGENTS.md:22
    severity: low
  - summary: >-
      An unpadded AVP followed by further octets still pulls the padded length, so three octets of the following AVP header are consumed.
    evidence: |-
      `DiameterAvpDecap` decodes one AVP per packet and has never supported a concatenated stream of unpadded AVPs: before this story the same input forwarded 17 misaligned octets instead of 9. Deciding between consuming, repairing and dropping such a stream is policy the story's intent does not set, and the message readers already reject unpadded AVPs inside a message.
    location: >-
      src/diameteravpdecap.cc:34
    severity: low
  - summary: >-
      `DiameterAvpEncap` dereferences a failed `push()` and now also an unchecked `put()`.
    evidence: |-
      Both calls return null only on allocation failure, which no config can reach. Pre-existing: the unchecked `push()` predates this story, and story 2 recorded the same call in `DiameterEncap` as deferred.
    location: >-
      src/diameteravpencap.cc:51
    severity: low
  - summary: >-
      An AVP value above 16,777,215 octets truncates the 24-bit AVP Length field while the padding still uses the full length.
    evidence: |-
      Pre-existing class: story 2 deferred the same 24-bit truncation for the message Length, no Click source in the tree produces such a packet, and adding a length-limit policy is behaviour the intent does not ask for.
    location: >-
      src/diameteravpencap.cc:47
    severity: low
baseline_revision: '116e879e62269920f59c91e0b96bbb8290f540c5'
---

<intent-contract>

## Intent

**Problem:** `DiameterAvpEncap` writes the AVP header and the untouched payload, so an 8-octet header plus a 5-octet value is 13 octets where RFC 6733 §4.1 requires 16, and `DiameterAvpDecap` returns the padding as if it were data. A receiver walking two consecutive AVPs therefore reads the second one three octets early (F-7).

**Approach:** The encoder appends the 0-3 zero padding octets the AVP needs and keeps the Length field at header-plus-data; the decoder truncates the packet to the declared AVP length, deriving the padding size from Length and never from the padding's content.

## Boundaries & Constraints

**Always:** Padding length is `getLengthPadded() - getLength()`, 0 to 3 octets; padding octets are zero; AVP Length excludes padding; element names, arguments, port counts and every existing `.click` config keep working; tabs, zero warnings at `-Wall -Wextra`; the shared header stays free of Click and userlevel-only includes. `DiameterPushAVP`'s padded encoding, the message walk and both pop elements keep emitting today's bytes.

**Never:** No new element, port, argument or drop class. No flag policy (story 5), no `RAND*`/seeding work (stories 4, 6), no `AC_INIT`, include-guard or `<iostream>` changes (story 8). Do not edit `SPEC.md` or `findings.md`. Do not make the decoder reject a standalone unpadded AVP.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| PAD_THREE | 5-octet payload into `DiameterAvpEncap(CODE 264)` | 16 octets: `00000108 0000000d 61626364 65000000` | No error expected |
| NO_PAD | 4-octet payload `7778797a` into the same element | 12 octets: `00000108 0000000c 7778797a` | No error expected |
| PAD_TWO | 2-octet payload `6162` into the same element | 12 octets: `00000108 0000000a 61620000` | No error expected |
| VENDOR_PAD | 5-octet payload into `DiameterAvpEncap(CODE 264, VENDORID 42)` | 20 octets: `00000108 80000011 0000002a 61626364 65000000` | No error expected |
| ROUNDTRIP | 5-octet payload through `DiameterAvpEncap` then `DiameterAvpDecap` | 16 octets out of the encoder, then the original 5 octets `61626364 65` | No error expected |
| TWO_CONSECUTIVE | 28-octet packet holding a 16-octet AVP (length 13) then a 12-octet AVP (length 12) | First decap leaves 12 octets `0000010c 0000000c 7778797a`; second leaves 4 octets `7778797a` | No warning |
| LEGACY_UNPADDED | 13-octet standalone AVP declaring length 13 into `DiameterAvpDecap` | 5 octets `61626364 65` | No error — tolerated, no new drop |

</intent-contract>

## Code Map

- `src/diameteravpencap.cc:44-47` -- `simple_action` pushes the header only and sets Length to `headerLength + p_in->length()`; the padding is missing and the 8/12 header choice duplicates `ah.getHeaderLength()`.
- `src/diameteravpdecap.cc:16-29` -- `pull(headerLength)` at 27 leaves the padding (and any trailing octets) in the packet, which is the defect; the guard already supplies `avpLength`.
- `src/diameter.hh:226-232` -- `AvpHeader::getLengthPadded()` and `getHeaderLength()` are the reuse points; do not repeat the rounding formula or the 12/8 choice.
- `src/diameter.hh:322-345` -- `diameter_check_avp` rejects a declared length below the header or past the packet, and its comment at 322-326 deliberately allows a standalone unpadded AVP.
- `src/diameterpushavp.cc:146-171` -- the reference encoder: pads, zeroes the pad with `memset`, and stores the unpadded length; leave it alone.
- `tests/configs/avp-roundtrip.click` -- the 5-octet round trip whose expectation moves from 13 to 16 octets.
- `tests/known-defects/f7-avp-padding.click` -- the repro to promote; it is the last file in the directory.
- `tests/smoke.bats:63-69` -- the `avp-roundtrip` expectation and its F-7 comment; `expect` compares whole output.
- `tests/README.md:36-93`, `README.md:169-213` -- the F-7 rows, the "today's bytes" paragraph, the known-defects section and the known-limitations bullet to correct.
- `findings.md:51-56` -- read-only F-7 evidence.

## Tasks & Acceptance

**Execution:**
- `src/diameteravpencap.cc` -- append `getLengthPadded() - getLength()` zero octets after the payload, push the header via `getHeaderLength()`, and keep Length as header plus data -- the encoder emits an aligned AVP.
- `src/diameteravpdecap.cc` -- truncate the packet to the declared AVP length before pulling the header -- the padding and any trailing octets leave the packet.
- `tests/configs/avp-padding.click`, `avp-padding-two.click`, `avp-padding-none.click`, `avp-padding-vendor.click`, `avp-two-decode.click`, `avp-decap-unpadded.click` -- one config per matrix row, so each pad size (3, 2, 0) and the vendor header are asserted separately -- CAP-3 byte assertions.
- `tests/smoke.bats` -- add a test per new config and move the `avp-roundtrip` expectation to 16 octets encoded and 5 decoded -- a regression to 13 octets fails the run.
- `tests/known-defects/f7-avp-padding.click` -- delete -- the directory then empties and goes away with the defect.
- `tests/README.md`, `README.md` -- move F-7 into the fixed behaviour, drop the known-defects section, and state the padding contract -- the docs describe the tree as it now behaves.

**Acceptance Criteria:**
- Given a 5-octet payload, when `DiameterAvpEncap(CODE 264)` runs, then the packet is 16 octets `00000108 0000000d 61626364 65000000` with zero padding octets (CAP-3).
- Given a 4-octet and a 2-octet payload, when both are encoded, then each packet is 12 octets and only the 2-octet one ends in `0000` padding.
- Given `VENDORID 42` and a 5-octet payload, when the element runs, then the AVP is 20 octets with a 12-octet header, flags `80`, Length `000011` and three zero pad octets.
- Given `DiameterAvpEncap` then `DiameterAvpDecap`, when a 5-octet payload passes, then it comes out byte for byte with no drop warning.
- Given two consecutive padded AVPs in one packet, when they are decoded in sequence, then the first yields the second AVP entire and the second yields its 4 data octets.
- Given a 13-octet standalone AVP declaring length 13, when it is decoded, then 5 octets are forwarded rather than dropped.
- Given the package on Click master, when built at `-Wall -Wextra` and the suite runs, then zero warnings, every test passes, and `tests/known-defects/` no longer exists.

## Spec Change Log

## Review Triage Log

### 2026-11-16 — Review pass
- verdicts: 29 findings — high 0, medium 0, low 25, false 2, maybe-false 0
- findings:
  - `[low]` `[defer]` `AGENTS.md:22` still says defect repros live in `tests/known-defects/`, which this change deletes — real; the fix edits an agent-context file, which triage defers.
  - `[low]` `[patch]` `src/diameter.hh:322-327` says an unpadded standalone AVP is tolerated "until F-7 lands" — real; the comment now states the tolerance is deliberate.
  - `[low]` `[patch]` the decoder's fallback branch silently `take`s every octet past the declared length, so a padded AVP plus 1-7 trailing octets loses them without a warning — real; the "more octets follow" test became `length() > paddedLength`, so trailing octets are forwarded instead of swallowed.
  - `[low]` `[defer]` an unpadded AVP followed by another AVP still pulls the padded length and eats 3 octets of the next header — real, but pre-existing: this element has always decoded one AVP per packet and never handled a concatenated unpadded stream; recorded in `deferred`.
  - `[low]` `[patch]` the branch threshold hardcodes `DIAMETER_AVP_HEADER_LENGTH` — real; the same patch selects on `> paddedLength`, so no minimum-header constant remains.
  - `[low]` `[patch]` the decoder re-decodes the header the guard already parsed — real; the padded length is computed locally as `(avpLength + 3) & ~3u`.
  - `[low]` `[defer]` `DiameterAvpEncap` dereferences a null `push()` and now also an unchecked `put()` — real but pre-existing class: the unchecked `push()` predates the story and story 2 deferred the same call in `DiameterEncap`; recorded in `deferred`.
  - `[low]` `[patch]` no config covers a one-octet pad or a zero-length value — real; `avp-padding-one.click` and `avp-padding-empty.click` were added with their tests.
  - `[false]` `[reject]` the story artifact lacks `## Auto Run Result`, has empty logs and records only expected verification — refuted: finalization writes the result and this pass appended the triage log; `in-review` is the step-04 status.
  - `[low]` `[patch]` `sprint-status.yaml` says `1-3: backlog` while the story is in review — real; set to `review` now and to `done` at finalization.
  - `[false]` `[reject]` F-7 is still open in `findings.md` with nothing reconciling it — refuted: that file is the epic's immutable evidence record (stories 1 and 2 established it), and `README.md`'s limitations list no longer names F-7, so its reproduction promise does not cover it.
  - `[low]` `[patch]` the `DiameterAvpDecap` table row and the decode contract do not describe the two behaviours, and "unpadded" carries two senses — real; both READMEs state the consume-or-forward rule after the patch.
  - `[low]` `[defer]` (edge) an unpadded AVP followed by 8 or more octets takes the padded pull — same defect and route as the unpadded-stream row above.
  - `[low]` `[defer]` (edge) `put()` can return null and is dereferenced — same defect and route as the unchecked-allocation row above.
  - `[low]` `[defer]` (edge) a value above 24 bits truncates the AVP Length field while the padding uses the full length — real but pre-existing class: story 2 deferred the same 24-bit truncation for the message Length; recorded in `deferred`.
  - `[low]` `[defer]` (edge) the `known-defects` deletion orphans `AGENTS.md` — same row and route as the first finding.
  - `[low]` `[reject]` (edge) the Execution bullet says the decoder truncates to the declared length while the code branches — real discrepancy, but its only fix edits the read-only intent-contract; the matrix row is the operative contract and every row passes.
  - `[low]` `[patch]` (verification gap) no config decodes a well-formed V-flag AVP, so an 8-octet pull for a 12-octet header would pass the suite — real; `avp-decap-vendor.click` added.
  - `[low]` `[patch]` (verification gap) a padded AVP plus 1-7 trailing octets loses them silently, and a legacy unpadded first AVP plus data mis-slices — the trailing-octet half is the selector row, fixed by the same patch; the legacy half is deferred with the unpadded-stream row.
  - `[low]` `[defer]` (verification gap) `AGENTS.md` still names the deleted directory — same row and route as the first finding.
  - `[low]` `[patch]` (verification gap) the one-octet pad size is never produced or consumed — same coverage row; `avp-padding-one.click` closes it.
  - `[low]` `[reject]` (intent) the Approach sentence says the decoder truncates to the declared length while the diff consumes the padded AVP — same row as the Execution-bullet finding; no route but reject, because the fix edits the intent-contract.
  - `[low]` `[patch]` (intent) the Problem's message-walking surface is asserted only at the element level; nothing joins `DiameterAvpEncap` to a message — real; `avp-encap-message.click` runs AvpEncap then Encap then PopAVP and pins the 20-octet message.
  - `[low]` `[patch]` (intent) the branch selector introduces an unspecified 1-7-octet regime — same selector row, fixed by the same patch.
  - `[low]` `[defer]` (intent) the tolerance rule is packet-size based and mis-slices a legacy unpadded AVP that is not alone — same row and route as the unpadded-stream finding.
  - `[low]` `[patch]` (intent) "never from the padding's content" has no assertion — real; `avp-decap-nonzero-pad.click` decodes a padded AVP whose pad octets are non-zero.
  - `[low]` `[patch]` (intent) vendor decoding is never exercised — same row as the vendor verification gap; the new config covers it.
  - `[low]` `[patch]` (intent) documentation is stale or inconsistent across `AGENTS.md`, `README.md` and `tests/README.md` — the README halves are the documentation row and are patched; the `AGENTS.md` half is deferred with the first finding.
  - `[low]` `[reject]` (intent) zero padding and the unpadded Length are asserted only transitively, and no test compares AvpEncap's AVP with PushAVP's — true but harmless: both byte forms are pinned by their own configs, so an equivalence assertion adds surface without new information.

## Design Notes

- **Decoder truncates, it does not reject.** `diameter_check_avp` deliberately accepts a standalone AVP whose declared length fits but whose padding does not (story 1 left it that way). Truncating to `avpLength - headerLength` is safe whether the pad is present or not, keeps legacy unpadded input decoding, and adds no drop class the intent did not ask for. Inside a message the walk already requires padded AVPs to sit inside it, so a message whose last AVP lacks its pad is dropped by the message readers, not here.
- **Length stays unpadded.** RFC 6733 §4.1 excludes padding from AVP Length; the message readers compare the message Length with the packet length and walk padded offsets, so a Length that counted the pad would mis-walk and fail the guard.
- **Padding is written explicitly.** `push()`/`put()` hand out uninitialized memory, so the pad octets are zeroed in the element rather than assumed.
- **Pre-fix probes** (2026-11-16, `$HOME/click-master` prefix, this baseline): the F-7 repro prints `avp-encap:   13 | 00000108 0000000d 61626364 65`; the two-AVP chain prints `avp1:   20 | 61626364 65000000 0000010c 0000000c 7778797a` and then drops with `DiameterAvpDecap: dropping malformed packet: AVP length below its header`. Reproduce both before editing.

## Verification

**Commands:**
- Export the working tree to WSL with LF endings; `autoconf && ./configure --with-click=$HOME/click-master --prefix=$HOME/click-master && make && make install` -- expected: zero warnings, `diameter.uo` installed.
- `CLICK=$HOME/click-master/bin/click $HOME/bats-core/bin/bats --tap tests` -- expected: every test passes, including the six new configs and the moved round-trip expectation.
- Rebuild or reuse `$HOME/click-asan`, install the package there, run the new configs and the full suite -- expected: exit 0, no sanitizer report.

**Manual checks (if no CLI):**
- Run `avp-padding.click` under `timeout 10` and count 16 octets with the last three zero; run `avp-two-decode.click` and confirm the two Print lines and no warning; run `avp-padding-vendor.click` and count 20 octets with a 12-octet header.

## Auto Run Result

Summary: `DiameterAvpEncap` now writes the 0-3 zero octets that pad an AVP to a 4-octet boundary and keeps the AVP Length at header plus value, so a 5-octet value is 16 octets instead of 13. `DiameterAvpDecap` derives the padding size from the AVP Length alone — `(Length + 3) & ~3` minus `Length` — and consumes the AVP whole when octets follow it, or forwards the value with the padding dropped when the AVP is the whole packet, so a legacy unpadded standalone AVP still decodes rather than being dropped. F-7's repro became asserted configs, the last file in `tests/known-defects/` is gone, and a message built from `DiameterAvpEncap` output now passes the message readers.

Files changed:
- `src/diameteravpencap.cc` — pads the AVP with zero octets after the value, uses `getHeaderLength()`/`getLengthPadded()`, keeps Length unpadded.
- `src/diameteravpdecap.cc` — padded length from the guard's `avpLength`, consume-whole or forward-value branches, padding never read.
- `src/diameter.hh` — `diameter_check_avp`'s comment states the tolerance is deliberate rather than pending F-7.
- `tests/configs/` — `avp-padding`, `avp-padding-one`, `avp-padding-two`, `avp-padding-none`, `avp-padding-empty`, `avp-padding-vendor`, `avp-two-decode`, `avp-decap-unpadded`, `avp-decap-vendor`, `avp-decap-nonzero-pad`, `avp-encap-message`; `avp-roundtrip` moved to 16 octets.
- `tests/smoke.bats` — eleven new tests, the round-trip expectation moved, header notes updated.
- `tests/known-defects/` — removed; F-7 was its last repro.
- `README.md`, `tests/README.md` — padding contract, decode contract, element rows, and the known-limitations F-7 bullet removed.

Review findings breakdown: 29 findings — high 0, medium 0, low 25, false 2, maybe-false 0. Patched: 9 entries (all low) — the decoder's "octets follow" test became `length() > paddedLength` so a padded AVP plus 1-7 trailing octets is forwarded instead of silently swallowed and no minimum-header constant remains; the second header decode was replaced by local rounding; the shared header's stale "until F-7 lands" comment; five configs plus tests closing the one-octet pad, empty value, vendor decode, non-zero pad and message-surface gaps; both READMEs' decode wording; and `sprint-status.yaml`. Deferred: 4 — `AGENTS.md` still names the deleted directory (agent-context file), the legacy unpadded multi-AVP stream still mis-slices (the element decodes one AVP per packet and never handled that input), the unchecked `push()`/`put()` in the encoder (pre-existing, story 2 deferred the same call), and the 24-bit AVP Length truncation (pre-existing class). Rejected: 2 false and 2 low — the story artifact's missing sections belong to finalization, which wrote them; `findings.md` is the epic's immutable evidence record and no longer appears in README's limitations list; the Execution bullet's "truncate to the declared length" wording can only be fixed by editing the read-only intent-contract, and every matrix row passes as written; an AvpEncap-to-PushAVP equivalence assertion adds no information because both padded byte forms are already pinned.

Follow-up review recommendation: false. Nine patched entries, all low, none high or medium — a first pass needs a patched high or two patched mediums to justify another pass.

Verification performed (WSL Ubuntu 26.04, GCC 15.2, against Click 2.1 built from upstream master `9197a594b`):
- Pre-fix probes on the baseline reproduced F-7: the repro printed `13 | 00000108 0000000d 61626364 65`, and the two-AVP chain printed 20 misaligned octets then dropped with `AVP length below its header`.
- Fresh LF export: `autoconf && ./configure --with-click && make && make install` — zero warnings, `diameter.uo` installed.
- `g++ -fsyntax-only -W -Wall -Wextra` over every `src/*.cc` — clean.
- `CLICK=... ~/bats-core/bin/bats --tap tests` — 39/39 pass, including all eleven new tests and the unchanged 28.
- AddressSanitizer: package rebuilt and installed into the ASan prefix (Click links `libasan`), full 39-test suite and every new config run — exit 0, no sanitizer report.

Residual risks: `linuxmodule` and `bsdpkg` cannot be built on this host, so their compilability rests on the change using only cross-platform `Packet` APIs (`push`, `put`, `take`, `pull`) and `memset`; the shared header gained no include. The decoder still consumes the padded length for an unpadded AVP followed by more data, which is deferred work. Padding beyond the AVP's own Length relies on the message walk, so an unpadded last AVP inside a message remains dropped by the message readers, as story 1 built it.

