---
title: 'Reject V=1 with Vendor-Id 0 on write and read'
type: 'bugfix'
created: '2026-11-17'
status: 'done'
baseline_revision: '876a56ba7a280ef61457fec43eb01c60228be290'
review_loop_iteration: 0
followup_review_recommended: false
context: ['{project-root}/AGENTS.md']
warnings: ['oversized']
deferred:
  - summary: >-
      A byte assertion cannot observe the initialised Vendor-Id, so removing the
      initialiser leaves the suite green.
    evidence: |-
      The configure guard turns on vendorId == 0, so the tests pass whether the
      initialiser is present or the stack slot happens to hold zero. The review
      layer rebuilt with `uint32_t vendorId;` and all three push-avp-vendor tests
      still passed, and the compiler stays warning-free at -O2 -Wall -Wextra
      -Wmaybe-uninitialized. Closing it needs MemorySanitizer over the configure
      path (a job shaped like the existing thread-sanitizer one) or a
      stack-poisoning harness; the SPEC confines pipeline work to the
      thread-safety story, so this is unverified deferred work.
    location: >-
      src/diameterpushavp.cc:82
    severity: medium (unverified)
  - summary: >-
      DiameterDecap and DiameterFlipRequest still forward a message that carries
      a V=1, Vendor-Id 0 AVP.
    evidence: |-
      Both elements validate through diameter_check_header() only and re-emit the
      payload unchanged, so a frame that arrives with the forbidden AVP leaves
      them still malformed. Story 2 covers the elements that walk AVPs (finding
      A-6, the Approach's "every element that walks AVPs"); putting the AVP walk
      into the two header-only rewriters is a separate change.
    location: >-
      src/diameterfliprequest.cc:16
    severity: low
---

<intent-contract>

## Intent

**Problem:** `DiameterPushAVP` declares its configured Vendor-Id as `uint32_t vendorId;` without an initialiser, so `VENDORSPEC true` without `VENDOR` copies an indeterminate stack slot into the 12-octet header; when it happens to be zero the AVP goes out as `V=1, Vendor-Id=0`, which RFC 6733 section 4.1.1 forbids outright (finding A-1, CAP-1). The receive side has the mirror hole: `diameter_check_avp()` sizes the header from the V bit and never reads bytes 8 to 11, so the same 12-octet `V=1, Vendor-Id=0` AVP is accepted and forwarded by every AVP reader (finding A-6, CAP-3).

**Approach:** Initialise the configured Vendor-Id, make configure fail when `VENDORSPEC` would emit a zero Vendor-Id (absent or explicitly `VENDOR 0`) with an error naming the argument, and add one shared reader check that drops `V=1` with a zero Vendor-Id so every element that walks AVPs inherits it. Writer and reader land in one change so they agree.

## Boundaries & Constraints

**Always:** A vendor AVP keeps the caller's non-zero Vendor-Id and flags `0x80`; non-vendor AVPs and every existing config keep their exact bytes; a dropped frame produces one warning naming the element and the reason and no output packet; tabs for indentation; the package stays warning-free at `-Wall -Wextra`.

**Never:** No new arguments (the `MANDATORY` argument is story 3, the `UINT32 0` length rule story 4, the conflicting-value check story 5); no message-level alignment or Version check (stories 6 and 7); no change to `DiameterAvpEncap`, whose `VENDORID` path already derives the V bit from a non-zero Vendor-Id; no default vendor identity, no repair or re-encoding of a bad AVP, and no edit to `DiameterRatedSource` or `.github/workflows/`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Writer, vendor AVP | `DiameterPushAVP(CODE 264, VENDORSPEC true, VENDOR 42, OCTETSTRING "abc")` on a 20-octet request | 36-octet frame, Length `0x24`, AVP flags `80`, AVP Length `0x0f`, Vendor-Id `0000002a`, value `61626300` | No error expected |
| Writer, no vendor id | `VENDORSPEC true` without `VENDOR`, and `VENDORSPEC true` with `VENDOR 0` | Configure fails before any packet is produced | Error names `VENDORSPEC` and `VENDOR` and cites RFC 6733 section 4.1.1 |
| Writer, non-vendor AVP | `push-avp.click`, `push-avp-rand.click`, the `rand-*` configs | bytes identical to the pre-change build | No error expected |
| Reader, standalone AVP | 12 octets `00000108 8000000c 00000000` into `DiameterAvpDecap` | packet dropped | `DiameterAvpDecap: dropping malformed packet: the V bit is set with a zero Vendor-Id` |
| Reader, AVP inside a message | 32-octet message carrying that AVP into `DiameterPopAVP` | packet dropped, same reason | `DiameterPopAVP: dropping malformed packet: the V bit is set with a zero Vendor-Id` |
| Reader, well-formed vendor AVP | `avp-decap-vendor.click` (Vendor-Id 42) | value `61626364 65` forwarded, unchanged | No error expected |

</intent-contract>

## Code Map

- `src/diameterpushavp.cc:72-108` -- `configure()`; `:79` is the uninitialised `uint32_t vendorId;`, `:81-93` the `Args` chain, `:95-105` the header fill. `#include <click/error.hh>` is missing and `errh->error()` needs it, as `src/diameterencap.cc:8` does.
- `src/diameterencap.cc:36-39` -- the configure-error style to follow: `return errh->error("the ERROR argument cannot be set on a request (RFC 6733 section 3)");`.
- `src/diameter.hh:276-313` -- the `DiameterCheck` enum and `diameter_check_reason()` switch; a new reason needs a case or it falls through to "unknown validation error".
- `src/diameter.hh:337-362` -- `diameter_check_avp()`: the V bit sets `headerLength` at `:350`, the short-header guard at `:351-352` guarantees bytes 8 to 11 exist, and the Length checks end at `:358`. Add the Vendor-Id test after them.
- `src/diameter.hh:364-396` -- `diameter_check_message()` calls `diameter_check_avp()` for every AVP, so `DiameterPushAVP`, `DiameterPopAVP` and `DiameterPopStorePushAVP` inherit the new check without edits.
- `src/diameteravpdecap.cc:18-26` -- the only reader that reports `diameter_check_avp()` directly; `src/diameteravpdecap.hh:33-52` enumerates its drop reasons and must gain the new one.
- `src/diameterpushavp.hh:21-62` -- the `=d` prose and the `VENDORSPEC`/`VENDOR` items; `tests/manpages.bats` renders this and requires both argument names in SYNOPSIS and DESCRIPTION.
- `src/diameteravpencap.hh:12-30` -- read-only model: `VENDORID` sets `vendorSpecific(true)` only when non-zero.
- `tests/smoke.bats:93-101` -- `expect_configure_failure` hard-codes `'DiameterEncap@2 :: DiameterEncap'`; `:526-529` and `:541-544` are its two callers; `:140-151` are the PushAVP byte tests; `:586-692` the `malformed-*` drop tests.
- `tests/configs/push-avp.click` -- the 20-octet request and `Print(MAXLENGTH 200, CONTENTS HEX)` shape every PushAVP config copies.
- `tests/configs/avp-decap-vendor.click` -- the well-formed vendor AVP that the new reader check must keep forwarding.
- `tests/README.md` -- the paragraph that says which configs assert the configure path and which assert the drop path.

## Tasks & Acceptance

**Execution:**
- `src/diameter.hh` -- add `DIAMETER_CHECK_VENDOR_ID_ZERO` beside the AVP reasons, its `diameter_check_reason()` case ("the V bit is set with a zero Vendor-Id"), and the test in `diameter_check_avp()` after the Length checks: when `headerLength == 12` and bytes 8 to 11 are all zero, return it -- one check every AVP walker inherits, placed after the structural guards so the bytes are known readable and Length faults keep their precedence.
- `src/diameterpushavp.cc` -- initialise `vendorId = 0`, include `<click/error.hh>`, and after `Args().complete()` return `errh->error(...)` when `vendorSpec` and `vendorId` are both zero -- removes the indeterminate read and makes both the absent and the explicit-zero form fail at configure time; the message names `VENDORSPEC` and `VENDOR` and cites RFC 6733 section 4.1.1.
- `src/diameterpushavp.hh` -- state in `=d` that `VENDORSPEC true` needs a non-zero `VENDOR` and that configure fails otherwise, and say "Required when VENDORSPEC is true and must be non-zero" in the `VENDOR` item -- the man page is the only place a caller learns this.
- `src/diameteravpdecap.hh` -- add the zero-Vendor-Id bullet to the enumerated drop reasons -- keeps the page truthful about what the element refuses.
- `tests/configs/push-avp-vendor.click` -- the vendor AVP happy path from the matrix -- the only existing coverage of `VENDORSPEC` is none, so this pins the bytes the writer must produce.
- `tests/configs/push-avp-vendor-missing.click` -- `VENDORSPEC true` with no `VENDOR` -- pins A-1 as a configure failure rather than an indeterminate header.
- `tests/configs/push-avp-vendor-zero.click` -- `VENDORSPEC true, VENDOR 0` -- pins that an explicitly zero Vendor-Id is refused too, not only the absent one.
- `tests/configs/malformed-avpdecap-vendor-id-zero.click` -- the standalone 12-octet AVP -- pins A-6 at the element that reads one AVP.
- `tests/configs/malformed-avp-in-message-vendor-id-zero.click` -- a 32-octet message carrying that AVP into `DiameterPopAVP` -- proves the shared check reaches the message walkers, not only the AVP reader.
- `tests/smoke.bats` -- change `expect_configure_failure` to take `CONFIG ELEMENT MESSAGE`, matching Click's `@line :: name` suffix with a wildcard, update its two existing callers, and add one test per new config -- one helper cannot stay bound to `DiameterEncap` now that a second element refuses a config.
- `tests/README.md` -- say the configure-path helper is per element and name the Vendor-Id cases among the drop and refusal configs -- the file currently claims exactly two configs are refused and that AVP alignment is what the `avp-*` tests pin.

**Acceptance Criteria:**
- Given the rebuilt package, when `CLICK=PREFIX/bin/click bats --tap tests` runs, then it exits 0 with every existing expectation unchanged.
- Given a 20-octet request and `DiameterPushAVP(CODE 264, VENDORSPEC true, VENDOR 42, OCTETSTRING "abc")`, when the frame is printed, then it is 36 octets with AVP flags `80`, AVP Length `0x0f`, Vendor-Id `0000002a` and value `61626300`.
- Given `VENDORSPEC true` with no `VENDOR` or with `VENDOR 0`, when Click configures the element, then it exits non-zero with the named error and no packet reaches `Print`.
- Given the 12-octet `V=1, Vendor-Id=0` AVP, when `DiameterAvpDecap` or `DiameterPopAVP` sees it, then exactly one drop warning naming that element and `the V bit is set with a zero Vendor-Id` is printed and no packet reaches `Print`.
- Given the pre-change package at `876a56b`, when the new configs run, then the two configure-failure configs configure and print a frame instead of failing, the four reader configs forward the frame instead of dropping it, and the three behaviour pins (`push-avp-vendor`, `push-avp-vendor-unused`, `malformed-avpdecap-vendor-id-zero-length`) still pass -- the negative control for both halves.

## Spec Change Log

## Review Triage Log

### 2026-11-17 — Review pass
- verdicts: 25 findings — high 0, medium 2, low 16, false 7, maybe-false 0
- findings:
  - `[low]` `[reject]` Design Notes say one test covers both VENDOR forms while Tasks add two configs — The fix is a spec edit, which this pass rejects; both configs stay, and the note's meaning is one code path with two caller-facing forms.
  - `[false]` `[reject]` "Only implementable reading" is contradicted by DiameterAvpEncap treating VENDORID 0 as non-vendor — The argument surfaces differ: VENDORSPEC true explicitly asks for a vendor header, while VENDORID 0 asks for a plain 8-octet header, so refusing V=1 with Vendor-Id 0 in PushAVP and deriving non-vendor in AvpEncap are the same RFC rule read against different arguments.
  - `[low]` `[reject]` "Nothing that works today starts failing" omits out-of-tree VENDORSPEC-without-VENDOR configs — Real but deliberate: such a config emits a forbidden Vendor-Id, so failing it is the fix; the sentence is spec prose whose correction this pass rejects.
  - `[low]` `[reject]` Code Map cross-references to diameterencap.cc are off by one — Verified: the include is at :9 and the first `return errh->error` at :40, not :8 and :36-39; a spec-prose correction, rejected here.
  - `[low]` `[reject]` Design Notes' "Length faults keep precedence" holds only inside diameter_check_avp — Verified: the padded-bound fault is raised by diameter_check_message after the check returns, so V=1/Vendor-Id-0 with a pad overhang reports the vendor reason; the fix is spec prose, rejected, while the precedence that does belong to the check is now pinned by the new length config.
  - `[low]` `[patch]` DiameterAvpDecap's drop-list lead-in says "cannot be read" but the new bullet is a readable, RFC-forbidden AVP — Patched: the lead-in now reads "cannot be read or carries a value the RFC forbids".
  - `[low]` `[patch]` The new man-page sentence "VENDOR is ignored when VENDORSPEC is false" is untested — Patched: `push-avp-vendor-unused.click` and its test pin the 32-octet non-vendor frame.
  - `[low]` `[patch]` Two of the four message walkers that inherit the check have no test — Patched: `malformed-avp-in-message-pushavp-vendor-id-zero.click` and `malformed-avp-in-message-popstorepush-vendor-id-zero.click` were added, each with an `expect_drop` test for its element.
  - `[low]` `[patch]` The message-side config carries one AVP, so it cannot show the walk checks every offset — Patched: a well-formed first AVP now precedes the zero-Vendor-Id AVP and the message Length is 0x2c.
  - `[low]` `[reject]` No test pins the new man-page prose — The repo's stated convention is that argument and documentation drift is caught at review; sentence-level man-page greps would add assertion surface for a case that convention already covers.
  - `[false]` `[reject]` New configs are listed under "Behavior that must keep working" — That heading describes the regression table, not the age of a config; every row, old or new, is an expectation that must keep passing.
  - `[low]` `[patch]` The README's receive-side index paragraph omits the Vendor-Id rule — Patched: it now names the V=1/Vendor-Id-0 drop, its reason and the Length precedence.
  - `[false]` `[reject]` The smoke.bats header comment covers four configs with three rule descriptions — The comment states four configs and the three refusal rules they exercise; the two Vendor-Id configs share one rule, so no case is missing.
  - `[low]` `[defer]` Header-only rewriters DiameterDecap and DiameterFlipRequest still forward a V=1/Vendor-Id-0 AVP — Pre-existing and outside this story's "every element that walks AVPs" scope; recorded as deferred work.
  - `[low]` `[reject]` expect_configure_failure now wildcards Click's @N element suffix, relaxing the pinned `DiameterEncap@2` — Verified as intentional: the spec's own task requires the wildcard because a second element now refuses a configuration; the element name stays pinned, only the instance index is free, and no committed config carries two instances of one element. Pinning it would restore the line-number brittleness the task removes.
  - `[low]` `[patch]` The new Vendor-Id reason's precedence over the Length fault is unpinned, and hoisting the test leaves the suite green — Pre-verified by the layer: a 12-octet AVP with V=1, Vendor-Id 0 and Length 8 reports `AVP length below its header` today, the hoisted build reports the vendor reason, and all 99 tests still pass. Patched with `malformed-avpdecap-vendor-id-zero-length.click` and its test; the mutation was rerun and now fails.
  - `[medium]` `[defer]` The initialised `vendorId` cannot be distinguished from an all-zero stack slot by any byte assertion, so removing the initialiser leaves the suite green — Pre-verified by the layer with a rebuilt package; closing it needs MemorySanitizer over the configure path or a stack-poisoning harness, a CI capability the SPEC confines to the thread-safety story. Deferred with its evidence.
  - `[false]` `[reject]` Writer expectations live at configure exit and error text while the reader's live at packet bytes — That split is the intent's own design: the writer's invalid case is refused at configure, and the matrix states it there.
  - `[medium]` `[defer]` The initialiser has no observation point in the diff — Same root cause as the verification-gap finding; deferred together as unverified work.
  - `[low]` `[patch]` The intent claims every AVP walker inherits the check but the tests exercise two of four — Same root cause as the blind hunter's coverage finding; patched by the two added walker configs.
  - `[low]` `[defer]` CAP-3's "no malformed frame leaves a rewriting element still malformed" reaches DiameterDecap and DiameterFlipRequest, which validate only the header — Same root cause as the deferred header-only-rewriter finding; deferred together.
  - `[false]` `[reject]` The baseline-fails evidence is prose rather than encoded in the tests — The intended procedure is a baseline install, which this pass ran: the nine new tests give three passes and six failures on `876a56b`.
  - `[false]` `[reject]` The configure-failure oracle is Click's diagnostic format rather than the package's — The package contributes the message text, which is asserted verbatim; Click's framing is stable output two existing tests already rely on.
  - `[low]` `[reject]` Design Notes' "one test covers both" reads against the two configs — Same finding as the blind hunter's first; the fix is spec prose, rejected.
  - `[false]` `[reject]` Test plumbing (`expect_configure_failure`'s signature) is not named by the contract — The contract governs behaviour, not test helpers, and the helper's strictness is unchanged apart from the mandated instance wildcard.

## Design Notes

The absent `VENDOR` and an explicit `VENDOR 0` are the same state after initialisation, so one test covers both: `vendorSpec && vendorId == 0` fails configure. That is the only implementable reading of "reject `VENDORSPEC true` without `VENDOR`" that also honours the RFC's "MUST NOT use the value of zero" for a caller who writes the zero out. No existing config uses `VENDORSPEC`, so nothing that works today starts failing.

The reader check sits after the three Length checks because those are structural: a frame whose Length already contradicts its header is reported as such, the same precedence `malformed-error-on-request-length.click` pins for the message header. The `short 12-octet vendor header` guard at `diameter.hh:351-352` is what makes the read of bytes 8 to 11 safe, so the new test must follow it.

Golden frame for the vendor happy path (20-octet request plus a 3-octet value and one pad octet):

```text
01000024 80000118 00000000 00000001 00000002 00000108 8000000f 0000002a 61626300
```

## Verification

**Commands:**
- `autoconf && ./configure --with-click=PREFIX --prefix=PREFIX && make && make install` -- expected: builds with no warnings under `-Wall -Wextra`
- `CLICK=PREFIX/bin/click bats --tap tests` -- expected: every test passes, including nine new ones
- `CLICK=PREFIX/bin/click bats --tap --filter 'push-avp-vendor|vendor-id-zero' tests` -- expected: the nine new configs pass together
- Negative control: install the package at `876a56b` into a second prefix and run the nine new tests against it -- expected: `push-avp-vendor`, `push-avp-vendor-unused` and `malformed-avpdecap-vendor-id-zero-length` pass (they pin behaviour the baseline already had), while the two configure-failure configs and the four reader configs fail

## Auto Run Result

Status: done

**Change.** `DiameterPushAVP` initialises its configured Vendor-Id and refuses `VENDORSPEC true` unless `VENDOR` is non-zero, so the uninitialised header A-1 describes can no longer reach the wire; `diameter_check_avp()` now rejects a 12-octet header whose Vendor-Id is zero, so every element that walks AVPs drops the receive-side mirror A-6 with one warning naming the reason. Writer and reader agree on the same RFC 6733 section 4.1.1 rule.

**Files changed.**
- `src/diameter.hh` -- `DIAMETER_CHECK_VENDOR_ID_ZERO` reason and the zero-Vendor-Id test in `diameter_check_avp()`, after the Length checks.
- `src/diameterpushavp.cc` -- `vendorId = 0` initialised; configure error when `VENDORSPEC` and a zero Vendor-Id meet; `<click/error.hh>` included.
- `src/diameterpushavp.hh` -- the vendor rule in `=d` and in the `VENDOR` item.
- `src/diameteravpdecap.hh` -- new drop-reason bullet and a widened lead-in for it.
- `tests/configs/push-avp-vendor.click` -- the vendor AVP happy path, 36 octets.
- `tests/configs/push-avp-vendor-missing.click`, `tests/configs/push-avp-vendor-zero.click` -- absent and explicit-zero refusals.
- `tests/configs/push-avp-vendor-unused.click` -- `VENDOR` ignored without `VENDORSPEC`.
- `tests/configs/malformed-avpdecap-vendor-id-zero.click`, `tests/configs/malformed-avpdecap-vendor-id-zero-length.click` -- the standalone drop and the Length-fault precedence.
- `tests/configs/malformed-avp-in-message-vendor-id-zero.click` -- a two-AVP message through `DiameterPopAVP`.
- `tests/configs/malformed-avp-in-message-pushavp-vendor-id-zero.click`, `tests/configs/malformed-avp-in-message-popstorepush-vendor-id-zero.click` -- the same check through the other two walkers.
- `tests/smoke.bats` -- `expect_configure_failure` takes the element name and wildcards Click's `@N` suffix; nine new tests.
- `tests/README.md` -- configure-path helper, new config rows, and the receive-side and precedence wording.

**Review.** One pass, 25 findings across four layers: high 0, medium 2, low 16, false 7. Seven findings patched (all low): the `DiameterAvpDecap` lead-in, the untested "VENDOR is ignored" sentence, the two walker configs, the two-AVP message config, the README index paragraph, and the unpinned Length precedence. Two entries deferred. Sixteen rejected: seven were false (the AvpEncap comparison, the README heading, the smoke comment, three descriptive intent-alignment surfaces, the test-plumbing note), and the rest were spec prose, a documented review-caught convention, or a helper relaxation the spec itself mandates.

**Follow-up review recommendation: false.** No high finding was patched and no medium entry was patched (both medium entries were deferred as unverified), so the pass converged.

**Verification.**
- `-Wall -Wextra`: a clean build of all ten sources, zero warnings (the `AC_OUTPUT` autoconf warning is pre-existing and unrelated).
- `CLICK=/tmp/opencode/click-mt/bin/click bats --tap tests`: 103/103, no skips.
- `--filter 'push-avp-vendor|vendor-id-zero'`: the nine new tests pass.
- Matrix audit: every intent-contract row is covered by a test that ran -- vendor AVP (21), both refusals (22, 23), non-vendor bytes (19, 20, 24, 25, 27, 28, 71), standalone drop (79), message drop (81), well-formed vendor AVP (43).
- Negative control against an installed `876a56b` package: three passes and six failures, exactly the predicted split.
- Mutation check: hoisting the Vendor-Id test above the Length checks changes the reported reason for the Length-fault frame and fails `malformed-avpdecap-vendor-id-zero-length`.

**Residual risks.** The initialiser itself stays unobservable to any byte assertion, and the two header-only rewriters still forward a forbidden AVP; both are recorded in `deferred`. The `@N` wildcard in `expect_configure_failure` means the failing instance index is not pinned, which no committed config can distinguish.
