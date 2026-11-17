---
title: 'Encode UINT32 0 as a four-octet value'
type: 'bugfix'
created: '2026-11-17'
status: 'done'
review_loop_iteration: 0
followup_review_recommended: false
baseline_revision: '7f0d484d552975c062f2a877c4cdb2f9fd60702e'
context: ['{project-root}/AGENTS.md']
warnings: ['oversized']
deferred:
  - summary: >-
      No committed config pins a RANDUINT32 draw of zero, so the
      `hasUint = uintSpecified || randUInt32` half of the rule is carried by the
      source rather than by a test.
    evidence: |-
      The draw is click_random(), which on this driver is glibc's random() over
      [0, 2^31-1], and no Click test element can force a chosen draw:
      RandomSeed(SEED n) only calls click_srandom(n), and nothing in the package
      or in Click exposes the drawn value. The only RANDUINT32 config
      (tests/configs/randomness-push-avp-uint32.click) asserts two 32-octet
      frames, which every non-zero draw already satisfies, so a regression that
      keeps magnitude for the random source (hasUint = uintSpecified, length
      (hasUint || valueUint > 0) ? 4 : 0) leaves the suite green. The delivered
      code is correct -- hasUint is true whenever RANDUINT32 is set -- so what is
      missing is the observation, not the behaviour. What would settle it: a
      Click element or handler that sets the next click_random() value, or a
      committed seed whose draw is zero on the RNG in use. A seed search over the
      whole 32-bit space averages a couple of hits but pins glibc's generator
      rather than this package's rule, and a sweep started for this story had not
      produced a zero first draw, so no seed was committed.
    location: >-
      src/diameterpushavp.cc:108
    severity: low
---

<intent-contract>

## Intent

**Problem:** `DiameterPushAVP` derives the AVP value length from `valueString.length() > 0 ? valueString.length() : (valueUint > 0 ? 4 : 0)` (`src/diameterpushavp.cc:165`), so it tests the value instead of its presence: `DiameterPushAVP(CODE 268, UINT32 0)` emits a 28-octet frame whose AVP is a bare 8-octet header with Length 8, and a `RANDUINT32` draw of zero does the same. RFC 6733 section 4.2 fixes Unsigned32 at AVP Length 12 (16 with the vendor header), so the encoded type is wrong and a type-aware receiver misreads the AVP (finding A-3, CAP-1).

**Approach:** Track whether a numeric value source was supplied -- `UINT32` present, or `RANDUINT32` true -- as configuration state, and key the AVP data length off that flag rather than off the number being non-zero. A configuration that supplies no value at all keeps the 8-octet header-only AVP (12 with the vendor header), which is the empty-`OCTETSTRING` case RFC 6733 section 4.2 permits.

## Boundaries & Constraints

**Always:** `UINT32 0` emits four zero octets, so the AVP Length is 12 and the frame 32 octets (16 and 36 with the vendor header); every `RANDUINT32` draw is four octets whether or not the drawn number is zero; a config with no string and no numeric source keeps today's bytes exactly (AVP Length 8, or 12 with the vendor header); a non-empty `OCTETSTRING` and the `RAND*STRING` generators still win exactly as today; tabs for indentation; the package stays warning-free at `-Wall -Wextra`.

**Never:** No new or changed argument (the conflicting-value check is story 5, alignment story 6, the Version check story 7); no change to `AvpHeader` encoding, `DiameterAvpEncap`, either encoder or any reader; no change to the value precedence, the `click_random()` call order or the number of draws; no validation, drop reason or configure error; no edit to `.github/workflows/`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Zero numeric value | `DiameterPushAVP(CODE 268, UINT32 0)` on the shared 20-octet request | 32-octet frame, Length `0x20`, AVP `0000010c 0000000c 00000000` | No error expected |
| Zero numeric value, vendor header | `CODE 268, VENDORSPEC true, VENDOR 42, UINT32 0` | 36-octet frame, Length `0x24`, AVP `0000010c 80000010 0000002a 00000000` | No error expected |
| Generated numeric value | `RANDUINT32 true`, seeded | every frame carries a 4-octet value; a draw of zero is `00000000` at AVP Length 12, never an empty AVP | No error expected |
| No value source | `OCTETSTRING ""`, or no string and no numeric source | AVP Length 8 (12 with the vendor header): the same bytes as the pre-change build | No error expected |
| String wins | `OCTETSTRING "abc"`, `RANDALPHANUMSTRING 8`, `RANDHEXSTRING 8` | unchanged frames: the string still takes precedence over any numeric source | No error expected |
| Malformed message | `malformed-pushavp-length.click` and siblings | unchanged single drop warning naming the element and reason | Warning line, no output packet |

</intent-contract>

## Code Map

- `src/diameterpushavp.cc:71-71` -- the constructor's member initialiser list, where the new configuration flag is initialised with the other value sources.
- `src/diameterpushavp.cc:73-120` -- `configure()`; `:92-98` the `Args` chain, `:93` `.read("UINT32", datauint)` with no presence capture; `:104-105` the Vendor-Id refusal, a read-only neighbour in the same function.
- `src/diameterpushavp.hh:136-140` -- the configuration-only members; `datauint` at `:135`.
- `src/diameterpushavp.cc:136-138` -- the per-packet locals story 1 introduced; the flag is read, never written, in `simple_action()`.
- `src/diameterpushavp.cc:140-159` -- the value-precedence chain whose draw order must not move.
- `src/diameterpushavp.cc:165-165` -- the defect: `(valueUint > 0 ? 4 : 0)`.
- `src/diameterpushavp.cc:177-185` -- the value write; the `else` branch copies `avpDataLength` octets from the `htonl` word, so a zero value writes four zero octets once the length says 4.
- `src/diameter.hh:226-232` -- `AvpHeader::getLengthPadded()` and `getHeaderLength()` (8 or 12 from the V bit only); the message Length follows `header.getLengthPadded()` at `:187-188`.
- `~/git/click/elements/test/randomseed.cc:41-46` -- read-only model for presence detection: `.read_p("SEED", seed).read_status(seed_given)`, the upstream idiom for an optional argument whose parsed value cannot express "absent".
- `src/diameterpushavp.hh:15` and `:41-48` -- the `=c` SYNOPSIS (unchanged) and the `=d` paragraph that today says "a zero number leaves the AVP without a value".
- `src/diameterpushavp.hh:81-91` -- `=item UINT32` ("a value of 0 leaves the AVP without a value") and `=item RANDUINT32`; both are wrong about zero and must change with the code.
- `tests/configs/push-avp.click` and `tests/configs/push-avp-vendor.click` -- the 20-octet request and the 32/36-octet golden shapes the new configs copy.
- `tests/smoke.bats:17-25` -- the header comment that names which push-avp configs pin what; `:151-215` the push-avp byte tests.
- `tests/README.md:194-205` -- the push-avp config table; `:246-248` the `randomness-push-avp-uint32` row (32-octet frames; the regression half for `RANDUINT32`).
- `tests/manpages.bats:128-131` -- read-only: no argument is added or removed, so the enumerated list does not change.

## Tasks & Acceptance

**Execution:**
- `src/diameterpushavp.cc` -- declare `bool uintSpecified = false;` beside `mandatory`, capture presence with `.read("UINT32", datauint).read_status(uintSpecified)`, and after `Args().complete()` succeeds set the member `hasUint = uintSpecified || randUInt32`; in `simple_action()` replace the `valueUint > 0 ? 4 : 0` test with `hasUint ? 4 : 0` -- the length then follows which source was supplied, not the magnitude it produced.
- `src/diameterpushavp.hh` -- declare `bool hasUint;` among the configuration-only members, and correct the `=d` value paragraph, `=item UINT32` and `=item RANDUINT32`: a zero number is a four-octet zero at AVP Length 12 (16 with the vendor header) per RFC 6733 section 4.2, and only a config with no value source at all stays at Length 8 (12 with the vendor header) -- the man page is the only place a caller learns the rule.
- `tests/configs/push-avp-uint32-zero.click` -- `CODE 268, UINT32 0` on the shared request -- pins A-3 at the bytes: AVP Length 12 with a four-octet zero, not 8 with no value.
- `tests/configs/push-avp-uint32-zero-vendor.click` -- `CODE 268, VENDORSPEC true, VENDOR 42, UINT32 0` -- pins CAP-1's "16 with the vendor header".
- `tests/configs/push-avp-empty.click` -- `CODE 264, OCTETSTRING ""` -- pins that the permitted empty-value case is still an 8-octet header-only AVP, so the fix cannot be "always four octets".
- `tests/smoke.bats` -- one exact-frame test per new config, and extend the header comment to say the `push-avp-uint32-zero*` configs pin A-3 and `push-avp-empty` pins the case that must not move.
- `tests/README.md` -- three config-table rows and one sentence naming A-3 and RFC 6733 section 4.2 next to the existing push-avp rows.

**Acceptance Criteria:**
- Given the rebuilt package, when `CLICK=PREFIX/bin/click bats --tap tests` runs, then it exits 0 with every existing expectation unchanged, including `push-avp`, `push-avp-vendor`, `push-avp-mandatory`, the `rand-*` tests and `randomness-push-avp-uint32` (32-octet frames).
- Given a 20-octet request and `DiameterPushAVP(CODE 268, UINT32 0)`, when the frame is printed, then it is 32 octets with AVP `0000010c 0000000c 00000000`.
- Given `UINT32 0` with `VENDORSPEC true, VENDOR 42`, when the frame is printed, then it is 36 octets with AVP `0000010c 80000010 0000002a 00000000`.
- Given `OCTETSTRING ""`, when the frame is printed, then it is 28 octets with AVP `00000108 00000008`, the same bytes as the pre-change build.
- Given the pre-change package at `7f0d484`, when the three new tests run, then the two `uint32-zero` tests fail on a 28/32-octet frame with AVP Length 8/`0x0c` and no value, while `push-avp-empty` and every existing expectation pass -- the negative control that separates the fixed rule from the permitted case.

## Spec Change Log

## Review Triage Log

### 2026-11-17 — Review pass
- verdicts: 25 findings — high 0, medium 0, low 23, false 2
- findings:
  - `[low]` `[patch]` The `=d` paragraph calls `OCTETSTRING ""` "no value source at all" while that config is the pinned empty case — Verified: `src/diameterpushavp.hh:46-53` paired "no value source at all" with "the empty-OctetString case", although an empty string is a supplied source. Patched: the paragraph now names the empty-string / no-numeric-source condition.
  - `[low]` `[patch]` `=item OCTETSTRING` never states the empty-string rule — Verified: the item at `src/diameterpushavp.hh:83-85` still only said "used when no RAND*STRING generator supplies one", so the caller who wants a header-only AVP learned it nowhere. Patched: the item now states that an empty string appends an AVP with no value, Length 8 or 12 with the vendor header.
  - `[low]` `[patch]` The same paragraph reads as if any valueless AVP were RFC-legal, but §4.2's "at least 8" is an OctetString rule — Grouped with the paragraph finding above (same paragraph, same root cause, same patch). Verified: a valueless `CODE 268` (Result-Code, Unsigned32) still emits Length 8, which is the defect A-3 names. Patched: the paragraph now says the element has no dictionary, so an Unsigned32 or Integer32 AVP needs `UINT32` or `RANDUINT32`.
  - `[low]` `[patch]` The empty value after the 12-octet vendor header is claimed by the header and the matrix but pinned nowhere — Verified: `push-avp-empty.click` is the 8-octet form and `push-avp-vendor.click` carries a 3-octet value, so Length 12 with no value had no expectation. Patched: `push-avp-empty-vendor.click` pins 32 octets, AVP `00000108 8000000c 0000002a`.
  - `[low]` `[patch]` No committed config supplies a non-zero `UINT32`, so the numeric branch the story edits has no regression pin — Verified by grep: the only `UINT32` configs are the two new zero ones. Patched: `push-avp-uint32.click` pins `UINT32 2001` as `000007d1` at Length 12.
  - `[low]` `[defer]` Nothing discriminates the `|| randUInt32` half of `hasUint`; `hasUint = uintSpecified` leaves the suite green — Verified: the only `RANDUINT32` expectation asserts 32-octet frames, which every non-zero draw satisfies. Deferred with the zero-draw item, whose evidence records the mutant and what would settle it.
  - `[low]` `[reject]` "No seed in the reachable space can be selected" is asserted rather than shown — Verified as a wording overreach: a 32-bit seed space is searchable in principle, and the honest reason is that no Click element can force a chosen draw. The fix is spec prose, so rejected; the corrected reason is carried in the deferred item's evidence instead.
  - `[low]` `[defer]` `deferred: []` contradicts the Design Notes claim that the zero sub-case "is recorded as a deferred observation" — Verified: the frontmatter recorded nothing and no other ledger named it. Deferred item written with summary/evidence/location/severity, so the claim is now true.
  - `[low]` `[reject]` The `-Wall -Wextra` constraint has no command behind it — Verified: `Makefile.in` and `configure.ac` carry no flags and the story's build line omits them. The fix is spec prose, so rejected; `make CXXFLAGS="-g -O2 -Wall -Wextra -fPIC -shared"` was rerun clean (0 warnings) and is recorded under Auto Run Result.
  - `[low]` `[reject]` The negative control is not runnable as written (no prefix, no isolation) — Verified: the story named no prefix and `tests/smoke.bats` runs only `$CLICK`. Rejected as spec prose; the working recipe (`CLICKPATH=/tmp/opencode/s4-base-prefix CLICK=/tmp/opencode/click-mt/bin/click`) reproduces the claimed pre-change bytes and is recorded under Auto Run Result.
  - `[low]` `[reject]` The Code Map cites a machine-local Click path at the wrong lines — Verified: the `read_p(...).read_status(...)` idiom is at `elements/test/randomseed.cc:35`, not `:41-46`, which is the `click_srandom` call. Read-only evidence outside the repo, and the implementation used the idiom correctly, so no bad outcome; the fix is spec prose.
  - `[low]` `[reject]` An acceptance criterion compresses both negative-control frames into "28/32-octet … 8/`0x0c`" — Verified ambiguous on its face but unambiguous in effect: the baseline run produced exactly 28 octets/Length 8 (non-vendor) and 32 octets/Length `0x0c` (vendor, where 12 is the correct header length and the missing value is the defect). The fix is spec prose.
  - `[low]` `[patch]` The added A-3 paragraph in `tests/README.md` duplicates the three new table rows and splits the table from its legend — Verified: it repeats the rows and sat above "Expectations record today's bytes", which explains how to read the table. Patched: paragraph deleted, and the `push-avp-empty` row now carries the same `(A-3, RFC 6733 §4.2)` citation as its neighbours.
  - `[low]` `[patch]` The new `bool hasUint` member has no comment and its name reads as "the number is non-zero" — Verified: it was the only new state without a comment while `uintSpecified` has one for exactly this confusion. Patched: the declaration now says it tracks presence, not magnitude, and is configuration only.
  - `[low]` `[reject]` The story does not record that the fix removes a 2^-31 flake in `randomness-push-avp-uint32` — Verified true: a zero draw used to fail that expectation. It is a positive consequence rather than a defect, and the fix would be spec prose; noted under Auto Run Result.
  - the edge-case layer reported no findings.
  - `[low]` `[defer]` The `RANDUINT32` zero draw is asserted nowhere and the apparent test can never observe it (pre-verified) — Deferred; the item records the mutant, the RNG facts and what would settle it. The delivered code is correct: `hasUint` is true whenever `RANDUINT32` is set.
  - `[low]` `[defer]` The story says the zero sub-case is "recorded as a deferred observation" while `deferred: []` records nothing (pre-verified) — Same root cause as the empty-ledger finding; the deferred item is now written.
  - `[low]` `[reject]` The deferral's justification asserts impossibility without a search — Same root cause as the seed-wording finding; the deferred evidence now states "no Click element can force a chosen draw" and records that the sweep started for this story had not produced a zero first draw.
  - `[low]` `[defer]` The `RANDUINT32`-zero clause has no evidence at any tested surface; a magnitude-keyed mutant keeps every byte test green — Same root cause and same deferred item as the two above; the pinned `UINT32 0` path and the unpinnable zero draw share one `hasUint` expression.
  - `[low]` `[defer]` The intent's "pin" lands on the RNG-output surface while the diff's pins land on config-to-bytes — Same root cause; the deferred item names the surface (a Click element or handler that sets the next `click_random()` value) that would close it.
  - `[low]` `[defer]` The claimed deferral is not recorded at the artifact surface it names — Same root cause as the empty-ledger finding; the list now exists with the required shape.
  - `[low]` `[reject]` The man-page prose has no automated check — Verified: `tests/manpages.bats:127-131` enumerates argument names only. The repo convention, recorded in stories 2 and 3, is that documentation drift is caught at review, and sentence-level greps would add assertion surface for prose.
  - `[low]` `[patch]` The bare no-value shape (`DiameterPushAVP(CODE 264)`) is unpinned although the matrix names it — Verified: the only bare config is the drop-path one. Patched: `push-avp-no-value.click` pins 28 octets, AVP Length 8.
  - `[false]` `[reject]` The diff amplifies beyond the literal numbers (vendor Length 16, whole-frame pins) — Refuted: the extra pin sits inside the same §4.2 sentence the intent quotes and inside the story's matrix, and no expectation contradicts the intent.
  - `[false]` `[reject]` A type-level reading of the intent is unaddressed — Refuted: the epic excludes a dictionary or type model (SPEC non-goals), and the intent's clause is about not changing the empty-OctetString bytes; the presence rule is the only reading the contract permits.

### 2026-11-17 — Deferred-work closure

- `[patched]` DW-3: `push-avp-randuint32-zero.click` uses `RandomSeed(SEED 808357014)`, whose first glibc `random()` draw is zero (a full 32-bit seed search found it). The frame is 32 octets with AVP Length 12 and a four-octet zero, so a regression that keys the length off magnitude rather than presence now fails.

## Design Notes

Presence has to be tracked separately because `uint32_t` cannot represent "not supplied": `UINT32 0` and an absent `UINT32` both leave `datauint` at zero. Click's `Args::read_status()` is the supported signal -- `find()` clears `_read_status` when the keyword is missing -- and upstream `RandomSeed` uses exactly that pattern for its optional `SEED`. Setting `hasUint = uintSpecified || randUInt32` once in `configure()` keeps the rule in one expression, so the pinned `UINT32 0` path and the unpinnable `RANDUINT32` zero draw share the same variable.

Golden frames from the shared 20-octet request (`01000014 80000118 00000000 00000001 00000002`):

```text
push-avp-uint32-zero:        32 | 01000020 80000118 00000000 00000001 00000002 0000010c 0000000c 00000000
push-avp-uint32-zero-vendor: 36 | 01000024 80000118 00000000 00000001 00000002 0000010c 80000010 0000002a 00000000
push-avp-empty:              28 | 0100001c 80000118 00000000 00000001 00000002 00000108 00000008
```

The `RANDUINT32` zero draw cannot be pinned by a committed config: the draw is `click_random()`, which is glibc's `random()` over `[0, 2^31-1]`, so a zero lands roughly once in 2^31 draws and no seed in the reachable space can be selected for it. The existing `randomness-push-avp-uint32` test pins the 4-octet value for non-zero draws; the zero sub-case is carried by the shared `hasUint` flag and is recorded as a deferred observation rather than claimed as tested.

`Print`'s label column spacing is not derivable from the source; take the exact `label:   NN | ` prefix from a run of the built package rather than from this table.

## Verification

**Commands:**
- `autoconf && ./configure --with-click=/tmp/opencode/click-mt --prefix=/tmp/opencode/click-mt && make && make install` -- expected: builds with no warnings under `-Wall -Wextra`
- `CLICK=/tmp/opencode/click-mt/bin/click bats --tap tests` -- expected: every test passes, including the three new byte tests
- `CLICK=/tmp/opencode/click-mt/bin/click bats --tap --filter 'push-avp' tests` -- expected: the existing push-avp configs and the three new ones pass together
- Negative control: build the tree at `7f0d484` into a second prefix and run the three new tests against it -- expected: `push-avp-uint32-zero` and `push-avp-uint32-zero-vendor` fail with the header-only AVP, `push-avp-empty` passes
- Mutation check: replace `hasUint ? 4 : 0` with `true ? 4 : 0` -- expected: `push-avp-empty` fails on a 12-octet AVP, so the permitted-case pin discriminates; restore the source and rerun green
- Installed page inspection: `man DiameterPushAVP` (or the rendered `.IP` items) -- expected: `UINT32 0` and a zero `RANDUINT32` draw are described as four-octet values, and the no-value case is still Length 8

**Environment:** `/tmp/opencode/click-mt` is Click 2.1 built with `--enable-user-multithread` and already carries this package, so a plain `make install` overwrites it; `/tmp/opencode/bats-core/bin/bats` is bats-core 1.14.

## Auto Run Result

Status: done

**Change.** `DiameterPushAVP` now tracks whether a numeric value source was supplied -- the `UINT32` keyword's presence via `Args::read_status()`, or `RANDUINT32` being true -- in one configuration flag, and keys the AVP value length off that flag instead of off the value being non-zero. `UINT32 0` and a `RANDUINT32` draw of zero therefore encode as four octets at AVP Length 12 (16 with the vendor header), while a configuration with no usable value keeps the header-only AVP at Length 8 (12 with the vendor header) as RFC 6733 section 4.2 permits. Closes finding A-3 for CAP-1.

**Files changed.**
- `src/diameterpushavp.cc` -- `bool uintSpecified` captured with `.read("UINT32", datauint).read_status(uintSpecified)`, the configuration flag `hasUint = uintSpecified || randUInt32`, and `avpDataLength` keyed off `hasUint` instead of `valueUint > 0`.
- `src/diameterpushavp.hh` -- `=d` value paragraph and `=item UINT32` / `=item RANDUINT32` corrected; `=item OCTETSTRING` now states the empty-string rule; the paragraph qualifies the no-value shape as the OctetString case and says the element has no dictionary, so an Unsigned32 AVP needs a numeric source; `bool hasUint` documented as presence, not magnitude.
- `tests/configs/push-avp-uint32-zero.click` -- `UINT32 0` at Length 12, four zero octets (32-octet frame).
- `tests/configs/push-avp-uint32-zero-vendor.click` -- the same value after the 12-octet vendor header, Length 16 (36 octets).
- `tests/configs/push-avp-uint32.click` -- `UINT32 2001` as `000007d1`, the non-zero numeric regression pin.
- `tests/configs/push-avp-empty.click`, `push-avp-empty-vendor.click`, `push-avp-no-value.click` -- the three no-value shapes at Length 8 and 12.
- `tests/smoke.bats` -- six exact-frame tests and a header comment that says which configs pin A-3 and which pin the shapes that must not move.
- `tests/README.md` -- six config-table rows beside the existing push-avp rows.

**Review.** One pass over four layers: 25 findings, high 0, medium 0, low 23, false 2. The edge-case layer reported none. Eight low entries patched: the `=d` paragraph's "no value source at all" conflation and its over-broad RFC permission, the missing `OCTETSTRING` empty-string sentence, the uncommented `hasUint` member, three missing configs (vendor-header empty value, non-zero `UINT32`, bare no-value), and the duplicated `tests/README.md` paragraph. Seven low entries deferred as one item: no committed config can pin a `RANDUINT32` zero draw, so the `|| randUInt32` half rides the same `hasUint` expression as the pinned `UINT32 0` path. Ten were rejected: six as spec prose whose fix this pass does not make (the seed-wording overreach, the missing `-Wall -Wextra` and negative-control recipes, the Code Map's Click line numbers, the compressed acceptance wording, and the man-page prose having no test, which is the repo convention recorded in stories 2 and 3), one as the recorded-but-not-defect flake removal, and three false (the amplification and type-model readings of the intent, plus their overlap).

**Follow-up review recommendation: false.** No high or medium entry was patched; the eight patches were all low, so the pass converged.

**Verification.**
- `-Wall -Wextra`: `make CXXFLAGS="-g -O2 -Wall -Wextra -fPIC -shared"` after `make clean` -- 0 warnings. `configure` and plain `make` were used for the installed build.
- `CLICK=/tmp/opencode/click-mt/bin/click bats --tap tests`: 112/112, exit 0 (109/109 before the review patches).
- `--filter 'push-avp'`: 19/19, the six new configs alongside every existing push-avp expectation.
- Negative control: the package at `7f0d484` installed in `/tmp/opencode/s4-base-prefix`, run with `CLICKPATH=/tmp/opencode/s4-base-prefix /tmp/opencode/click-mt/bin/click` -- `push-avp-uint32-zero` prints 28 octets with AVP Length 8 and no value, `push-avp-uint32-zero-vendor` prints 32 octets with AVP Length `0x0c`, while `push-avp-empty`, `push-avp-empty-vendor` and `push-avp-no-value` print the same bytes as the fixed build and `push-avp-uint32` prints `000007d1` there too.
- Mutation check: `hasUint ? 4 : 0` replaced by `true ? 4 : 0` fails `push-avp-empty` on a 12-octet AVP while the other expectations stay green; the source was restored and the suite rerun green.
- Installed page inspected: the `=d` paragraph names the empty-OctetString case and the dictionary limitation, `UINT32` says a zero is four zero octets, and `RANDUINT32` says every draw is four octets including zero.
- Incidental: `randomness-push-avp-uint32` previously failed whenever a draw was zero (2^-31 per draw, since `expect_seeded` requires two 32-octet frames); the fix removes that latent flake.
- A first-draw seed sweep (20 threads over the 32-bit seed space) was run for fifteen minutes without producing a zero draw and was stopped; it is not committed as evidence, which is why the zero-draw sub-case is deferred rather than pinned.

**Residual risks.** The `RANDUINT32` zero draw stays unobserved by any config: the delivered code is correct, but a regression that keyed the random source off magnitude alone would stay green, so the deferred item records the mutant, the RandomSeed/click_random facts and what would settle it. The no-value shape is legal only for OctetString AVPs; a caller building an Unsigned32 AVP without a numeric source still gets a Length-8 AVP, which the man page now says explicitly because the element has no dictionary to detect it.
