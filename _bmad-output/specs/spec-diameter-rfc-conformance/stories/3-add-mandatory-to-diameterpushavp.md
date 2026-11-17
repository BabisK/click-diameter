---
title: 'Add MANDATORY to DiameterPushAVP'
type: 'feature'
created: '2026-11-17'
status: 'done'
baseline_revision: '5c853093e636c7664ffe2c59391ac160283e4b77'
review_loop_iteration: 0
followup_review_recommended: false
context: ['{project-root}/AGENTS.md']
warnings: ['oversized']
deferred:
  - summary: >-
      No test pins that a received AVP with M set survives the package's own
      decode and re-encode, so a regression that clears `mandatory` in
      `AvpHeader::decode()` stays green.
    evidence: |-
      DiameterPopStorePushAVP decodes the popped AVP into its AvpHeader member
      and re-encodes it when the value is pushed back, and every other AVP walker
      reads the flags octet, but no committed config carries an AVP with M=1
      (`popstorepush-roundtrip.click` uses flags 00). Pre-existing: an M=1 frame
      was reachable on receive before this story; the story only made it reachable
      from the package's own writer. Closing it needs a config whose hand-written
      frame carries flags 40 and a byte assertion over the re-encoded output.
    location: >-
      src/diameter.hh:239
    severity: low
  - summary: >-
      A repeated keyword argument silently keeps the last value, so
      `MANDATORY true, MANDATORY false` configures and emits M=0.
    evidence: |-
      Verified against the built package: both orders configure and the second
      value wins. This is Click's Args behaviour for every keyword argument in
      every element (VENDOR, CODE, OCTETSTRING included), not something this
      story introduced; rejecting repeats would need package-wide duplicate
      detection rather than a change to one element.
    location: >-
      src/diameterpushavp.cc:87
    severity: low
---

<intent-contract>

## Intent

**Problem:** `DiameterPushAVP` hard-wires the AVP M bit to zero (`ah.setMandatory(false)` at `src/diameterpushavp.cc:104`) and offers no argument that can set it, so every AVP it appends is nonconformant for the base-protocol AVPs RFC 6733 registers as mandatory -- Origin-Host, Origin-Realm, Destination-Realm, Session-Id, Result-Code -- and a strict peer is entitled to reject the message. `DiameterAvpEncap` already takes `MANDATORY`, so the two AVP writers disagree about the same bit (finding A-2, CAP-1).

**Approach:** Add a `MANDATORY` boolean argument that sets the M bit, defaulting to false so every existing configuration keeps its exact bytes, and document it in the element header so `make install` renders it on the man page.

## Boundaries & Constraints

**Always:** `MANDATORY` absent and `MANDATORY false` both emit flags with M clear, byte-identical to today; `MANDATORY true` sets M (0x40) and changes no other octet of the frame; the M bit composes with the V bit (0x80) when `VENDORSPEC` is true; the argument is documented in both the `=c` SYNOPSIS and a `=d` item; tabs for indentation; the package stays warning-free at `-Wall -Wextra`.

**Never:** No change to `AvpHeader` encoding, which already models the M bit at `src/diameter.hh:263`; no validation, drop reason or reader change; no other new or changed argument (the `UINT32 0` length rule is story 4, the conflicting-value check story 5); no edit to `DiameterAvpEncap`, `DiameterPushAVP`'s value precedence, or `.github/workflows/`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| M set | `DiameterPushAVP(CODE 264, MANDATORY true, OCTETSTRING "abc")` on the 20-octet request | 32-octet frame, Length `0x20`, AVP group `4000000b`: M set, Length 11, value `61626300` | No error expected |
| M set with V | `MANDATORY true, VENDORSPEC true, VENDOR 42, OCTETSTRING "abc"` | 36-octet frame, Length `0x24`, AVP `c000000f 0000002a 61626300`: M and V both set, vendor header | No error expected |
| Default absent | `push-avp.click`, `push-avp-rand.click`, `push-avp-vendor.click`, `push-avp-vendor-unused.click`, `smp-push-avp.click` | bytes identical to the pre-change build; flags `00` (`80` for the vendor config) | No error expected |
| Explicit false | `MANDATORY false, OCTETSTRING "abc"` | same 32 octets as `push-avp.click`, flags `00` | No error expected |

</intent-contract>

## Code Map

- `src/diameterpushavp.cc:73-116` -- `configure()`; `:79-82` the initialised locals `vendorSpec`/`vendorId`, the style the new `mandatory` local follows; `:84-95` the `Args` chain ending in `.complete()`; `:103-105` `ah.setCode` / `ah.setMandatory(false)` / `ah.setVendorSpecific` -- the hard-wired false is at `:104`.
- `src/diameteravpencap.cc:14-41` -- read-only model: `bool mandatory = false;` at `:18`, `.read("MANDATORY", mandatory)` at `:23`, `ah.setMandatory(mandatory)` at `:28`.
- `src/diameteravpencap.hh:15` and `:48-50` -- the SYNOPSIS slot and the `=item MANDATORY` wording to mirror.
- `src/diameter.hh:230` and `:263` -- `getHeaderLength()` is 8/12 from the V bit only, and `encode()` writes flags as `(vendorSpecific << 7) | (mandatory << 6)`: M is 0x40, V is 0x80, so the two compose without touching the encoder.
- `src/diameterpushavp.hh:15` -- the `=c` SYNOPSIS lists ten arguments; `:23-28` the `=d` prose that claims "an M bit that is always clear" and must be corrected; `:50-106` the keyword list, `=item VENDOR` at `:63-67` is where `=item MANDATORY` belongs; `:110` the `=a` cross-references.
- `tests/configs/push-avp.click` -- the 32-octet golden whose AVP group is `00000108 0000000b` (M clear).
- `tests/configs/push-avp-vendor.click` -- the 36-octet golden with AVP group `00000108 8000000f 0000002a`: V set, M clear.
- `tests/smoke.bats:145-184` -- the push-avp byte tests and the two configure-failure tests; `:18-20` the file comment that names which push-avp configs pin what.
- `tests/manpages.bats:128-131` -- the `DiameterPushAVP` man-page test that enumerates every argument name in ten-argument form.
- `tests/README.md:194-199` -- the config table rows to extend; `:175-181` the configure-path paragraph stays true because the new argument never errors.
- `README.md:178` -- the element reference row listing `DiameterPushAVP`'s arguments.

## Tasks & Acceptance

**Execution:**
- `src/diameterpushavp.cc` -- declare `bool mandatory = false;` beside `vendorSpec`, add `.read("MANDATORY", mandatory)` after `.read("VENDOR", vendorId)`, and pass it to `ah.setMandatory(mandatory)` in place of the literal `false` -- the write happens once in `configure()`, so `simple_action()`'s per-packet header copy inherits the bit without touching the data path.
- `src/diameterpushavp.hh` -- add `MANDATORY` to the `=c` SYNOPSIS after `VENDOR`, replace "an M bit that is always clear" in `=d` with the M bit coming from `MANDATORY`, and add a `=item MANDATORY` after `=item VENDOR`: Boolean, sets the AVP M bit required by the AVP's application specification (RFC 6733 section 4.1), default false -- the man page is the only place a caller learns the argument exists.
- `tests/configs/push-avp-mandatory.click` -- `CODE 264, MANDATORY true, OCTETSTRING "abc"` -- pins A-2 at the bytes: flags `40` rather than `00`.
- `tests/configs/push-avp-mandatory-vendor.click` -- `MANDATORY true, VENDORSPEC true, VENDOR 42, OCTETSTRING "abc"` -- pins that M and V occupy their own bits of the same flags octet (flags `c0`).
- `tests/configs/push-avp-mandatory-false.click` -- `MANDATORY false, OCTETSTRING "abc"` -- pins that the argument's false value is M clear, not "argument present means set".
- `tests/smoke.bats` -- one test per new config, each an exact `expect` line, and extend the file comment to say which configs pin the M bit -- the push-avp tests are exact-bytes assertions, so M=0 on the five existing configs is the regression half.
- `tests/manpages.bats` -- add `MANDATORY` to the `DiameterPushAVP` argument list and retitle the test from ten to eleven arguments -- an undocumented argument fails this test.
- `tests/README.md` -- three config-table rows for the new configs -- the table is the index of what each config covers.
- `README.md` -- add `MANDATORY` to the `DiameterPushAVP` element-reference row and mention the M bit -- the top-level reference lists each element's arguments.

**Acceptance Criteria:**
- Given the rebuilt package, when `CLICK=PREFIX/bin/click bats --tap tests` runs, then it exits 0 with every existing expectation unchanged, including `push-avp`, `push-avp-rand`, `push-avp-vendor`, `push-avp-vendor-unused` and `smp-push-avp`, whose pinned flags keep M clear.
- Given a 20-octet request and `DiameterPushAVP(CODE 264, MANDATORY true, OCTETSTRING "abc")`, when the frame is printed, then it is 32 octets with AVP group `4000000b` and value `61626300`.
- Given `MANDATORY true` with `VENDORSPEC true, VENDOR 42`, when the frame is printed, then it is 36 octets with AVP group `c000000f 0000002a` and value `61626300`.
- Given `MANDATORY false`, when the frame is printed, then it is byte-identical to `push-avp.click`.
- Given the installed prefix, when `tests/manpages.bats` runs, then `DiameterPushAVP` names `MANDATORY` in both SYNOPSIS and DESCRIPTION.
- Given the pre-change package at `5c85309`, when the three new configs run, then each fails to configure with `MANDATORY: unknown argument` -- the negative control for the argument and the bit.

## Spec Change Log

## Review Triage Log

### 2026-11-17 — Review pass
- verdicts: 18 findings — high 0, medium 0, low 12, false 6
- findings:
  - `[low]` `[reject]` Code Map claims the configure-path paragraph "stays true because the new argument never errors", and the `tests/README.md` sentence "every other encap-* and push-avp* config configures and prints bytes" — Pre-verified: `MANDATORY 2` and `MANDATORY maybe` do fail with `MANDATORY: parse error`, so the Code Map sentence is wrong in general; the README sentence is about the committed configs and stays true, since none supplies an invalid boolean. The fix is spec prose, rejected.
  - `[false]` `[reject]` The matrix has no row or config for an unparsable `MANDATORY` — The only error path is Click's `BoolArg`, shared by every boolean argument in the package (`VENDORSPEC`, `RANDUINT32`, `REQUEST`, `ERROR`), none of which pins a parse error; the failure is a loud configure error naming the argument, and the two VENDOR refusals pin an RFC rule rather than a parse error.
  - `[low]` `[reject]` The matrix and an acceptance criterion say "AVP group `4000000b`" while the tests and Design Notes use `00000108 4000000b`, and "group" is applied to a flags-and-length fragment — Verified: `00000108` is the code word, so the shorter form is ambiguous in spec prose, but every committed expectation carries the full header. The fix is spec prose, rejected.
  - `[low]` `[patch]` The `smoke.bats` comment calls all push-avp tests exact-byte assertions and claims every config omitting `MANDATORY` pins M=0 — Verified false: `push-avp-rand`, `smp-push-avp` and the `rand-*` tests match patterns, and the `randomness-*` and `malformed-*` configs never cover the AVP header. Patched: it now says whole-frame comparisons, literal or pattern, and limits the M=0 claim to the existing expectations that cover the AVP header.
  - `[low]` `[reject]` The Verification mutation check names only three failures from forcing `ah.setMandatory(true)`, while every other flags-pinning expectation also breaks — True; the check is a demonstration of discrimination, not an exhaustive prediction, and the fix is spec prose, rejected.
  - `[false]` `[reject]` The Code Map cites `DiameterAvpEncap(CODE [, VENDORID, MANDATORY])` as the slot to mirror, yet PushAVP inserts `MANDATORY` before `OCTETSTRING` — Click keyword arguments are order-independent and the two element lists differ; `MANDATORY` sits with the header arguments it modifies, and nothing in the intent requires shared positions.
  - `[low]` `[patch]` `=item MANDATORY` is ambiguous about the direction of the bit and omits its independence from V and from both lengths — Patched: the item now says the M bit tells a receiving peer support is required, names 0x40 against V's 0x80, and states it changes neither the AVP nor the message Length; the page was re-rendered and inspected.
  - `[low]` `[defer]` Nothing checks that an M=1 AVP survives the package's decode and re-encode, which `DiameterPopStorePushAVP` performs — Verified: no committed config carries an AVP with M set, so a regression clearing the field in `AvpHeader::decode()` stays green. Pre-existing, since M=1 frames were reachable on receive before this story; recorded as deferred.
  - `[low]` `[reject]` The argument list lives in three hand-maintained places and only the man-page list is machine-checked — No drift exists today, and the repo convention (stated in `tests/README.md` and applied in story 2's review) is that argument and documentation drift is caught at review; a grep assertion would add surface for prose.
  - `[low]` `[reject]` No new config varies the value source with `MANDATORY` set — The bit is set on the configured header in `configure()` and every value branch inherits it, and both header forms (8- and 12-octet) are pinned; a `UINT32` config would re-pin the same line with no new observed invariant.
  - `[low]` `[defer]` `MANDATORY true, MANDATORY false` configures and the last value silently wins — Verified against the built package: both orders configure and the second value decides. That is Click `Args` behaviour for every keyword argument of every element, not introduced by this story; rejecting repeats needs package-wide duplicate detection. Recorded as deferred.
  - `[low]` `[patch]` The comment claims all push-avp tests are exact-byte assertions while `push-avp-rand` and `smp-push-avp` use patterns — Same root cause as the earlier comment finding; patched by the same rewrite.
  - verification-gap layer reported no findings.
  - `[false]` `[reject]` The intent's "a new tests/configs config" became three — Three is a superset of the requested pin; the extra two pin M+V composition and the explicit-false value, and neither contradicts the intent.
  - `[false]` `[reject]` The confirmation that existing configs still emit M=0 is a non-change with no committed assertion — The existing expectations are the assertion: `push-avp`, `push-avp-rand`, `push-avp-vendor`, `push-avp-vendor-unused`, `encap-push-pop`, the `rand-*` tests and `smp-push-avp` pin the AVP header and passed unchanged. "Confirm" asks for evidence, not new code.
  - `[false]` `[reject]` The intent's "conformant base-protocol AVP" is asserted in prose while the tests only pin a settable bit — The SPEC constraint selects the reading: `MANDATORY` defaults to false so existing bytes are preserved, and the story is the argument plus a caller's opt-in; conformance-by-default is explicitly excluded.
  - `[low]` `[reject]` The man-page test checks the argument name only, not its default or meaning — Same class as the sentence-level documentation checks story 2's review rejected: the behavioural half (default false, M clear without the argument) is pinned by the byte tests, and review catches prose drift.
  - `[false]` `[reject]` The story file carries a verification plan but no recorded results, and `sprint-status.yaml` is untouched — `## Auto Run Result` and the final status are written at Finalize, after review, so the reviewed tree is mid-run; `sprint-status.yaml` is the caller's orchestration state, outside build-auto.
  - `[low]` `[reject]` Unstated decisions the diff resolves: argument order, a `configure()` local rather than a member, and documentation scope wider than the header — The local follows story 1's per-packet-copy design, the order groups the header arguments, and the extra docs are harmless; none diverges observably from the intent, and a correction would be spec prose.

### 2026-11-17 — Deferred-work closure

- `[patched]` DW-1: `popstorepush-mandatory.click` sends a 32-octet frame whose AVP has flags `40` through `DiameterPopStorePushAVP`; the first output is the 20-octet header and the second re-encodes the stored AVP with M still set. A regression that clears `mandatory` in `AvpHeader::decode()` now fails.
- `[patched]` DW-2: a shared duplicate-keyword check in `src/diameterconf.hh` runs in `DiameterEncap`, `DiameterAvpEncap`, `DiameterPushAVP` and `DiameterRatedSource` before `Args`. A keyword given twice fails configuration naming it instead of Click's silent last-wins. `push-avp-duplicate-octetstring.click`, `encap-duplicate-code.click` and `rated-source-duplicate-rate.click` pin the keyword-only, positional-plus-keyword and value-source shapes; the man page and both READMEs state the rule.

## Design Notes

The M bit lives in the AVP flags octet, `0x40`, and the V bit is `0x80`; `AvpHeader::encode()` already writes both from members, so the only code change is to stop passing the literal `false`. Keeping the declared local `bool mandatory = false;` rather than a member of `DiameterPushAVP` is deliberate: `configure()` sets the header once and `simple_action()` copies the configured `AvpHeader` per packet (story 1), so the data path gains nothing to race on.

Golden frames, all derived from the 20-octet request the push-avp configs share (`01000014 80000118 00000000 00000001 00000002`):

```text
push-avp-mandatory:        32 | 01000020 80000118 00000000 00000001 00000002 00000108 4000000b 61626300
push-avp-mandatory-vendor: 36 | 01000024 80000118 00000000 00000001 00000002 00000108 c000000f 0000002a 61626300
push-avp-mandatory-false:  32 | 01000020 80000118 00000000 00000001 00000002 00000108 0000000b 61626300
```

`Print`'s label column spacing is not derivable from the source; take the exact `label:   NN | ` prefix from a run of the built package rather than from this table. The AVP group is the part the argument moves.

## Verification

**Commands:**
- `autoconf && ./configure --with-click=/tmp/opencode/click-mt --prefix=/tmp/opencode/click-mt && make && make install` -- expected: builds with no warnings under `-Wall -Wextra`
- `CLICK=/tmp/opencode/click-mt/bin/click bats --tap tests` -- expected: every test passes, including the three new byte tests and the eleven-argument man-page test
- `CLICK=/tmp/opencode/click-mt/bin/click bats --tap --filter 'push-avp' tests` -- expected: the existing M=0 configs and the three new M configs pass together
- Negative control: install the package at `5c85309` into a second prefix and run `click tests/configs/push-avp-mandatory*.click` -- expected: each exits non-zero with `MANDATORY: unknown argument`, and that prefix's `push-avp.click` still prints the unchanged 32-octet frame
- Mutation check: build with `ah.setMandatory(true)` instead of the argument -- expected: `push-avp`, `push-avp-vendor` and `push-avp-mandatory-false` print flags `40`/`c0` instead of `00`/`80` and fail, while the two M-set configs still pass; drop the `.read("MANDATORY", ...)` line -- expected: all three new configs fail at configure with `MANDATORY: unknown argument`, the same shape as the baseline

**Environment:** `/tmp/opencode/click-mt` is a Click built with `--enable-user-multithread` and already carries the story-2 package, so a plain `make install` overwrites it. `/tmp/opencode/bats-core/bin/bats` is bats-core 1.14; `bats --tap tests` with `CLICK=/tmp/opencode/click-mt/bin/click` is the whole check, and the three `smp-*` tests run rather than skip on that prefix.

## Auto Run Result

Status: done

**Change.** `DiameterPushAVP` now takes a `MANDATORY` boolean that sets the AVP M bit, defaulting to false so the existing configs that pin the AVP header stay M clear, and the argument is documented in the element header so the installed man page carries it. Three configs pin M=1 alone, M=1 composed with V, and an explicit false, closing finding A-2 for CAP-1.

**Files changed.**
- `src/diameterpushavp.cc` -- `bool mandatory = false;`, `.read("MANDATORY", mandatory)` after `VENDOR`, and `ah.setMandatory(mandatory)` replacing the hard-wired `false`.
- `src/diameterpushavp.hh` -- `MANDATORY` in the `=c` SYNOPSIS, the "always clear" prose replaced, and a `=item MANDATORY` stating what the bit tells a peer, that it is independent of V, and that it changes neither length.
- `tests/configs/push-avp-mandatory.click` -- `MANDATORY true` with the shared 20-octet request: 32 octets, AVP `00000108 4000000b`.
- `tests/configs/push-avp-mandatory-vendor.click` -- `MANDATORY true, VENDORSPEC true, VENDOR 42`: 36 octets, AVP `00000108 c000000f 0000002a`.
- `tests/configs/push-avp-mandatory-false.click` -- explicit false, byte-identical to `push-avp.click`.
- `tests/smoke.bats` -- three exact-frame tests and a comment that says which existing configs pin the AVP header and why that is the M=0 regression half.
- `tests/manpages.bats` -- the `DiameterPushAVP` page test now enumerates eleven arguments.
- `tests/README.md` -- three config-table rows.
- `README.md` -- `MANDATORY` in the element-reference row, noting it sets the M bit.

**Review.** One pass over four layers: 18 findings, high 0, medium 0, low 12, false 6; the verification-gap layer reported none. Two low entries patched -- the `smoke.bats` coverage comment (which overstated both its literal-byte claim and its M=0 coverage) and the `=item MANDATORY` wording -- and two low entries deferred (an M=1 AVP never traverses decode/re-encode in any test; duplicate keyword arguments silently last-win, which is Click-wide). Six findings were false: the parse-error coverage demand, the argument-position comparison with `DiameterAvpEncap`, and the auditor's config count, confirmation-surface, opt-in-versus-conformant, and mid-run-evidence observations. Six were rejected as spec prose or as the documentation convention review already covers: the "never errors" Code Map sentence, the "AVP group" notation, the mutation blast radius, the hand-maintained argument lists, the value-source coverage, and the unstated decisions. Arguments for the two patches, the patch attempts, and every finding's evidence are in the triage log.

**Follow-up review recommendation: false.** Two low entries were patched and no high or medium entry was patched, so the pass converged.

**Verification.**
- `-Wall -Wextra`: clean build of all ten sources, no compiler diagnostics.
- `CLICK=/tmp/opencode/click-mt/bin/click bats --tap tests`: 106/106, no skips.
- `--filter 'push-avp'`: 13/13; the M=0 configs and the three new ones pass together.
- Existing configs still emit M=0: `push-avp` and `push-avp-vendor-unused` keep `0000000b`, `push-avp-vendor` keeps `8000000f`, `push-avp-rand` keeps `00000010`, `encap-push-pop` keeps `0000000d`, and the `rand-*` and `smp-push-avp` expectations are unchanged.
- M=1: `push-avp-mandatory` prints `push-avp-mandatory:   32 | 01000020 80000118 00000000 00000001 00000002 00000108 4000000b 61626300`; `push-avp-mandatory-vendor` prints `... 36 | 01000024 ... 00000108 c000000f 0000002a 61626300`; `push-avp-mandatory-false` is byte-identical to `push-avp`.
- Negative control: against the package at `5c85309` in `/tmp/opencode/s3-base-prefix`, each new config exits 1 with `MANDATORY: unknown argument`, and that prefix's `push-avp` still prints the unchanged 32-octet frame.
- Mutation checks: with `ah.setMandatory(true)` in place of the argument the M=0 expectations print `40`/`c0` and fail while the two M-set configs pass; with `.read("MANDATORY", ...)` removed all three new configs fail at configure with `MANDATORY: unknown argument`. The source was restored and the suite rerun green.
- Installed page inspected: `MANDATORY` appears in SYNOPSIS and as a `.IP "MANDATORY"` item carrying the new wording.

**Residual risks.** The man-page test asserts only that the argument name appears, not the prose, so a stale prefix can serve an old page; that happened once here when `make install` wrote to the prefix recorded in a stale `Makefile`, and reconfiguring before installing fixed it. The M bit stays opt-in: `DiameterPushAVP(CODE 264, OCTETSTRING "host")` still emits M=0, which is the SPEC's constraint rather than a defect. The two deferred items are recorded with their locations and evidence.
