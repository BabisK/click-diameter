---
title: 'Story 4: Fix RANDALPHANUMSTRING length and the hex alphabet'
type: 'bugfix'
created: '2026-11-16'
status: 'in-progress'
review_loop_iteration: 0
followup_review_recommended: false
context: ['{project-root}/AGENTS.md']
warnings: ['oversized']
deferred: []
baseline_revision: '661e82b2f57c381d6e568db5d5e7e715916b89b6'
---

<intent-contract>

## Intent

**Problem:** `DiameterPushAVP`'s generators do not produce what their arguments promise. `RANDALPHANUMSTRING N` compares the count with a boolean (`randAlphaNumString > true`), so a count of 1 falls through every branch and appends an AVP with no value (F-8), and the hex alphabet literal is `"0123456789ABCDEFG" "abcdefg"`, so `RANDHEXSTRING` can emit `G`/`g` and doubles the case of `A`-`F` (F-9). A user who asks for one character gets none, and a value documented as hex can carry a digit that is not one.

**Approach:** Compare the count against zero like the other three generators, and make the hex alphabet exactly `0-9` and `A`-`F`, so each `RAND*STRING N` emits exactly N characters from the set its name states.

## Boundaries & Constraints

**Always:** Each `RAND*STRING N` generator emits exactly N characters; `RANDHEXSTRING` draws only from `0`-`9` and `A`-`F`; `RANDNUMSTRING` and `RANDALPHASTRING` keep today's alphabets; the AVP framing, padding and message Length stay as story 3 left them; tabs, zero warnings at `-Wall -Wextra`; element names, arguments, port counts and every existing `.click` config keep working.

**Never:** No change to the RNG itself — `srand`/`rand` are story 6's; no flag policy (story 5); no `AC_INIT`, include-guard or `<iostream>` work (story 8); no new argument, element or AVP type; do not make the generated values deterministic. Do not edit `SPEC.md` or `findings.md`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| ALNUM_ONE | 20-octet request through `DiameterPushAVP(CODE 264, RANDALPHANUMSTRING 1)` | 32 octets: `01000020 80000118 00000000 00000001 00000002 00000108 00000009 <ch> 000000` — AVP Length 9, one character, three zero pad octets | No error expected |
| ALNUM_EIGHT | Same header, `RANDALPHANUMSTRING 8` | 36 octets, AVP Length `00000010`, 8 characters, no padding | No error expected |
| HEX_ALPHABET | Same header, `RANDHEXSTRING 10000` | 10,020 octets; every one of the 10,000 value octets is in `0`-`9` or `A`-`F`; AVP Length `00002718`, message Length `00002724` | No error expected |
| HEX_ONE | `RANDHEXSTRING 1` | AVP Length 9: exactly one character, never an empty AVP | No error expected |
| OTHER_GENERATORS | `RANDNUMSTRING 4`, `RANDALPHASTRING 4` | 12-octet AVP each, 4 characters from `0`-`9` and from the ASCII letters | No error expected |

</intent-contract>

## Code Map

- `src/diameterpushavp.cc:127` -- `randAlphaNumString > true` is the F-8 defect; lines 131, 135, 139 already use `> 0` and are the pattern to copy. The count is `size_t` (`src/diameterpushavp.hh:27-30`), so the comparison promotes `true` to 1 and is false only at a count of 1.
- `src/diameterpushavp.cc:35-38` -- the `hex[]` literal `"0123456789ABCDEFG" "abcdefg"`; line 64 indexes it with `rand() % (sizeof(hex)-1)`, so the fix is the literal alone, not the loop.
- `src/diameterpushavp.cc:21-70` -- `randString()` appends one character per iteration and returns the string; `AlphaNum` (23-26), `Num` (28-29) and `Alpha` (31-33) are correct and stay untouched.
- `src/diameterpushavp.cc:144-171` -- the AVP writer that consumes `datastring`: `avpDataLength` from `datastring.length()`, `avpLengthPadded` rounds to 4 octets, the pad is `memset` to zero. Byte expectations follow from here; do not change it.
- `tests/configs/push-avp-rand.click:3-6` -- the existing `RANDALPHANUMSTRING 8` config; its comment says "8 hex characters", which is wrong for an alphanumeric generator.
- `tests/smoke.bats:50-55` -- the `push-avp-rand` test and its `[0-9a-f]{8} [0-9a-f]{8}` regex (the value is printed as hex octets, so 8 characters are 16 hex digits). `run_click` (22-28) runs one config under a 10 s timeout; `expect` (31-33) compares the whole output.
- `tests/README.md:36-80` -- the config table to extend; `README.md:132-134` and `README.md:197-212` -- the generator sentence and the F-8/F-9 known-limitations bullet.
- `_bmad-output/specs/spec-diameter-package-hardening/findings.md:58-69` -- read-only F-8/F-9 evidence.

## Tasks & Acceptance

**Execution:**
- `src/diameterpushavp.cc` -- change line 127 to `randAlphaNumString > 0` and the hex literal at 35-38 to `"0123456789ABCDEF"` -- F-8 and F-9, the two defects the story names.
- `tests/configs/rand-alphanum-one.click`, `rand-hex-one.click`, `rand-hex-alphabet.click`, `rand-num-four.click`, `rand-alpha-four.click` -- one config per matrix row, each with its own `Print` label -- CAP-4 byte assertions.
- `tests/smoke.bats` -- one test per new config; the alphabet test decodes the printed hex octets and fails on the first one outside `0`-`9`/`A`-`F` -- a `G`/`g` regression fails the run, and a count-1 regression shows an 8-octet AVP instead of 9.
- `tests/configs/push-avp-rand.click`, `tests/README.md` -- correct the "8 hex characters" wording and add the new rows -- the harness describes the arguments it exercises.
- `README.md` -- state each generator's alphabet and that N is exact, and drop the F-8/F-9 bullet from Known limitations -- the docs describe the tree as it now behaves.

**Acceptance Criteria:**
- Given a 20-octet request, when `DiameterPushAVP(CODE 264, RANDALPHANUMSTRING 1)` runs, then the packet is 32 octets with AVP Length `00000009` and one character followed by three zero pad octets (CAP-4, F-8).
- Given `RANDALPHANUMSTRING 8`, when the element runs, then the packet is 36 octets with AVP Length `00000010` and eight characters (CAP-4).
- Given `RANDHEXSTRING 10000`, when the element runs, then all 10,000 value octets are in `0`-`9`/`A`-`F` and the message is 10,020 octets (CAP-4, F-9).
- Given `RANDHEXSTRING 1`, when the element runs, then the AVP Length is 9 rather than 8.
- Given `RANDNUMSTRING 4` and `RANDALPHASTRING 4`, when both run, then each appends a 12-octet AVP with four characters from its own alphabet.
- Given the package on Click master, when built at `-Wall -Wextra` and `bats --tap tests` runs, then zero warnings and every test passes, including the unchanged `push-avp-rand` expectation.

## Spec Change Log

- **HEX_ALPHABET byte count corrected (2026-11-16).** The I/O matrix and the
  third acceptance criterion say `RANDHEXSTRING 10000` yields a 10,020-octet
  message with message Length `00002724`, but they also require AVP Length
  `00002718` (8 + 10000). A 20-octet header plus that 10,008-octet AVP is
  10,028 octets, message Length `0000272c`; 10,020 would need an AVP of 10,000
  and therefore a 9,992-character value. The implementation and
  `tests/configs/rand-hex-alphabet.click` assert the consistent figures —
  10,028 octets, AVP Length `00002718`, message Length `0000272c`, 10,000 value
  octets — since the AVP Length and the 10,000-character count are the point of
  the row and the totals follow from the writer at `src/diameterpushavp.cc:144-171`.

## Review Triage Log

## Design Notes

- **The count check, not the generator, was F-8's defect.** `randString()` was always correct; only the comparison at the call site made a count of 1 skip every branch and leave `datastring` empty, so the AVP fell back to the `datauint > 0 ? 4 : 0` rule and emitted a header-only AVP.
- **Hex is upper case only.** RFC 6733 AVP values are octets, not text, so either case is legal on the wire; the argument is named hex and CAP-4 forbids both `G` and `g`, so the alphabet is the 16 digits `0`-`9A`-`F`. Dropping the lower-case run also removes the double weighting `A`-`F` had over `0`-`9`.
- **The alphabet test decodes, it does not grep the text.** `Print` renders the value as hex octets, so a literal `G` would appear as `47` and a plain text search for `G` would prove nothing; the test re-reads the octets and checks each one against the alphabet.
- **Pre-fix probes** (2026-11-16, `$HOME/click-master` prefix, this baseline): `RANDALPHANUMSTRING 1` prints `28 | ... 00000108 00000008`, and a `RANDHEXSTRING` sample of a few hundred characters contains `47` (`G`) and `67` (`g`). Reproduce both before editing.

## Verification

**Commands:**
- Export the working tree to WSL with LF endings; `autoconf && ./configure --with-click=$HOME/click-master --prefix=$HOME/click-master && make && make install` -- expected: zero warnings, `diameter.uo` installed.
- `CLICK=$HOME/click-master/bin/click bats --tap tests` -- expected: every test passes, including the five new configs and the unchanged `push-avp-rand` expectation.
- Install into the AddressSanitizer prefix and run the full suite -- expected: exit 0, no sanitizer report.

**Manual checks (if no CLI):**
- Run `rand-alphanum-one.click` and count 32 octets with AVP Length `00000009`; run `rand-hex-alphabet.click` and confirm every value octet is `30`-`39` or `41`-`46`.
