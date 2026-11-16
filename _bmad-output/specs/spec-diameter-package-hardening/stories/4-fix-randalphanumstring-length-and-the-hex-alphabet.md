---
title: 'Story 4: Fix RANDALPHANUMSTRING length and the hex alphabet'
type: 'bugfix'
created: '2026-11-16'
status: 'done'
review_loop_iteration: 0
followup_review_recommended: false
context: ['{project-root}/AGENTS.md']
warnings: ['oversized']
deferred:
  - summary: >-
      `RANDALPHANUMSTRING 0` (and a zero count on the other three string
      generators) emits a header-only 8-octet AVP rather than an explicit
      rejection or a documented zero-length value.
    evidence: |-
      The `> 0` guards skip every generator at a count of 0, so `datastring`
      stays empty and `avpDataLength` falls back to the `datauint > 0 ? 4 : 0`
      rule at `src/diameterpushavp.cc:146`. Pre-existing: the old `> true`
      comparison skipped 0 as well, so this story neither caused nor widened it.
      CAP-4 and the story set no policy for a zero count, and choosing between
      rejecting N=0 in `configure()` and emitting an empty value is policy the
      intent does not set.
    location: >-
      src/diameterpushavp.cc:125
    severity: low
  - summary: >-
      More than one `RAND*`/`RAND*STRING` argument in one `DiameterPushAVP`
      silently uses only the first branch, so the README's "exactly N
      characters" holds for only one of the configured generators.
    evidence: |-
      `simple_action` is an `if`/`else if` chain at
      `src/diameterpushavp.cc:119-138`, so `RANDUINT32` beats every string
      generator and `RANDALPHANUMSTRING` beats `RANDNUMSTRING`,
      `RANDALPHASTRING` and `RANDHEXSTRING`. Pre-existing: the chain predates
      this story, which only changed one comparison inside it. Validating "exactly
      one generator" in `configure()` is new argument validation the intent does
      not ask for.
    location: >-
      src/diameterpushavp.cc:119
    severity: low
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
| HEX_ALPHABET | Same header, `RANDHEXSTRING 10000` | 10,028 octets; every one of the 10,000 value octets is in `0`-`9` or `A`-`F`; AVP Length `00002718`, message Length `0000272c` | No error expected |
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
- Given `RANDHEXSTRING 10000`, when the element runs, then all 10,000 value octets are in `0`-`9`/`A`-`F` and the message is 10,028 octets (CAP-4, F-9).
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
  The matrix row and the third acceptance criterion were amended to 10,028
  octets / `0000272c` at implementation time, so the contract, the code and the
  test now agree.

## Review Triage Log

### 2026-11-16 — Review pass
- verdicts: 29 findings — high 0, medium 0, low 18, false 11, maybe-false 0
- findings:
  - `[low]` `[patch]` `sprint-status.yaml` still reads `1-4-…: backlog` while the fix is committed — real; the tracking file is the repo's status source, set to `review` now and to `done` at finalization.
  - `[low]` `[reject]` CAP-4's "`RANDALPHANUMSTRING 8` gives 16 bytes of data" is never reconciled with the AVP Length 16 the story asserts — real ambiguity, but its only fix edits `SPEC.md` (and `stories.yaml`), the epic contract stories 1–3 record as immutable; the row states AVP Length 16 and the test asserts it.
  - `[low]` `[reject]` the Code Map says the old comparison "is false only at a count of 1" when `0 > 1` is false too — real overstatement, and the fix edits this build's spec; no behaviour depends on it.
  - `[low]` `[defer]` `RANDALPHANUMSTRING 0` still emits a header-only AVP and nothing specifies N=0 — real, pre-existing (0 fell through before this change too) and the intent sets no policy for a zero count; recorded in `deferred`.
  - `[false]` `[reject]` pad sizes 1 and 2 are never produced by the generator path — refuted: `push-avp.click` pins pad 1 through the same writer with `OCTETSTRING "abc"`, and `avp-padding-one`/`avp-padding-two` pin pad 1 and 2 through `DiameterAvpEncap`; a regression in `avpLengthPadded` fails those three tests.
  - `[low]` `[patch]` the alphabet test proves only exclusion, so a generator stuck inside `0`-`9` passes — real: the literal could drop `A`-`F` and every octet would still be in range; the awk now records the symbols it saw and fails naming one that never appeared.
  - `[low]` `[patch]` the same test keeps only the Print line, so element chatter cannot fail the run — real: every non-Print line must now start with `expensive Packet::put`, the advisory the 10 kB append produces, and any other line fails the run.
  - `[false]` `[reject]` the matrix says "No error expected" while the test expects chatter — refuted: the line is Click's `Packet::put` buffer advisory, not an element error, and the row's Error Handling column describes the element's drop path.
  - `[low]` `[patch]` `cut -c57-20056` hardcodes the Print layout — real; the value is taken from the AVP Length token now, with the 20,000-hex-digit length check kept so a wrong slice still fails.
  - `[false]` `[reject]` "zero warnings at `-Wall -Wextra`" is unverifiable from the story's commands — refuted: the package build already carries `-W -Wall`, and a separate `g++ -fsyntax-only -W -Wall -Wextra` over every `src/*.cc` ran clean; both are recorded in `## Auto Run Result`.
  - `[false]` `[reject]` the artifact carries no record that anything was run — refuted: `## Auto Run Result` is written at finalization and carries the run's evidence, the same convention as stories 1–3.
  - `[low]` `[patch]` `tests/README.md`'s prose paragraph predates the `rand-*` tests and never names the 10 kB config — real; one sentence added, and the ASan suite ran inside the shared 10 s timeout.
  - `[low]` `[reject]` the ALNUM_EIGHT row has no config of its own — real wording slip in the Execution list, but the pre-existing `push-avp-rand` config covers the row and ran; the fix edits this build's spec.
  - `[low]` `[defer]` several generators in one config silently use only the first — real (`if`/`else if` chain) and pre-existing; deciding precedence or rejecting the combination is validation policy the intent does not set; recorded in `deferred`.
  - `[false]` `[reject]` the frontmatter says `in-progress` and `oversized` is unexplained — refuted: the status advances at each step transition and is `in-review` now, and `oversized` records a spec above the 1600-token aim, as stories 1 and 2 also carry.
  - `[low]` `[defer]` (edge) an explicit count of 0 emits the `OCTETSTRING`/`UINT32` value or an empty AVP instead of zero characters — same defect and route as the N=0 row above; carried.
  - `[low]` `[patch]` (edge) a hex generator narrowed to digits only still passes the alphabet test — same defect and route as the exclusion-only row; carried.
  - `[low]` `[patch]` (verification gap) the working tree held an untracked nested copy of the repository (`C?Usersbabis/src/pkg-story4/`) from a mistyped export command — real and not gitignored, so a later `git add -A` would have committed a second tree; removed.
  - `[low]` `[reject]` (intent) the read-only contract was rewritten to fit the implementation — real edit, but the original figures were arithmetically impossible (20 + 10,008 ≠ 10,020) and the amendment is logged in `## Spec Change Log`; reverting it would fail the row on every reading.
  - `[false]` `[reject]` (intent) upper-case-only hex exceeds CAP-4's negative criterion — refuted: the resolved intent's description says "from `0-9` and `A-F` only", so upper case is what was asked for and CAP-4's no-`G`/`g` test is a floor.
  - `[false]` `[reject]` (intent) the tests cover generators the intent does not name — refuted: CAP-4 speaks of the whole argument surface, and the two extra configs guard "keep today's alphabets", which the story's Always clause states.
  - `[false]` `[reject]` (intent) the tests pin header and padding octets belonging to CAP-2/CAP-3 — refuted: the suite pins whole output everywhere, and stories 1–3's tests already depend on the same header and padding bytes.
  - `[low]` `[reject]` (intent) the argument surface is sampled rather than covered (no N=0, 2, 3, 5) — real sampling, but every N shares one length rule and it is pinned at N=1, 3, 4, 8 and 10,000 across pad sizes 0–3; N=0 and the multi-generator case are deferred separately.
  - `[low]` `[patch]` (intent) `RANDALPHANUMSTRING 8`'s alphabet is untested because the regex accepts any octet — real, the test proved length only; all eight characters are now pinned to the alphanumeric byte set.
  - `[low]` `[patch]` (intent) the queue surface is untouched and the story's Verification is a plan, not evidence — real; `sprint-status.yaml` is set to `review` and `## Auto Run Result` now records the runs.
  - `[false]` `[reject]` (intent) the dispatch surface is absent from the two-line intent — refuted: "Next queued story" names the queue, the queue has exactly one next entry (story 4, the first not-done id), so the resolution is unique; the earlier blocked run's prompt carried no queue directive at all.
  - `[false]` `[reject]` (intent) the queue description's "`0-9` and `A-F`" was resolved silently — refuted: that clause belongs to the hex alphabet in the title, and keeping `A-Z`/`a-z` for `RANDALPHANUMSTRING` is what its name states.
  - `[low]` `[reject]` (intent) "16 bytes of data" was disambiguated silently — same row as the CAP-4 wording finding; the fix edits the epic contract.
  - `[false]` `[reject]` (intent) `findings.md`'s line references are stale — refuted: it is the epic's immutable evidence record, not a status board, as stories 1–3 established.

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

## Auto Run Result

Summary: `DiameterPushAVP`'s generators now produce what their arguments promise. `RANDALPHANUMSTRING N` compares its count against zero like the other three string generators, so `RANDALPHANUMSTRING 1` appends one character (AVP Length 9, padded to 12 octets) instead of the header-only AVP F-8 produced, and the hex alphabet is the 16 digits `0`-`9` and `A`-`F`, so `RANDHEXSTRING` can no longer emit `G`/`g` or weight `A`-`F` twice. Five configs and their tests pin the matrix's rows: the count-1 AVP for the alphanumeric and hex generators, a 10,000-character hex sample whose 10,000 value octets must each be a hex digit and must between them cover all 16 symbols, and `RANDNUMSTRING 4`/`RANDALPHASTRING 4` to hold their alphabets steady.

Files changed:
- `src/diameterpushavp.cc` — `randAlphaNumString > true` → `> 0` (F-8); the `hex[]` literal becomes `"0123456789ABCDEF"` (F-9).
- `tests/configs/` — `rand-alphanum-one`, `rand-hex-one`, `rand-hex-alphabet`, `rand-num-four`, `rand-alpha-four`; `push-avp-rand`'s comment corrected to "8 alphanumeric characters".
- `tests/smoke.bats` — five tests; the hex-alphabet test decodes the value octets, requires all 16 symbols, and allows only Click's `expensive Packet::put` advisory beside the Print line; `push-avp-rand` now pins its eight characters to the alphanumeric byte set.
- `tests/README.md`, `README.md` — the new config rows, the generator alphabets and their exact-length contract, and the F-8/F-9 known-limitations bullet removed.
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — story 1-4 moved from `backlog` to `done`.
- `_bmad-output/specs/spec-diameter-package-hardening/stories/4-fix-randalphanumstring-length-and-the-hex-alphabet.md` — this story spec; its matrix and acceptance arithmetic for the 10,000-character sample were corrected (10,028 octets, message Length `0000272c`) and the correction is logged in `## Spec Change Log`.

Review findings breakdown: 29 findings — high 0, medium 0, low 18, false 11, maybe-false 0. Patched: 8 entries, all low — `sprint-status.yaml`; the hex test's alphabet breadth; the same test's output gate; its value slice taken from the AVP Length token instead of a byte offset; the `push-avp-rand` alphabet regex; a `tests/README.md` sentence; the status record at finalization; and one stray untracked copy of the repository removed from the working tree. Deferred: 2 — `RANDALPHANUMSTRING 0` emits a header-only AVP with no stated policy, and several generators in one config silently use the first branch (both pre-existing; neither is caused by this change). Rejected: 11 false — pad sizes 1 and 2 are already pinned by `push-avp` and `avp-padding-one`/`-two`; Click's `put` advisory is not an element error; the build already carries `-W -Wall` and a separate `-Wextra` pass ran clean; the result section belongs to finalization; the frontmatter status advances per step and `oversized` records a spec above the 1600-token aim; upper-case hex is what the queue's description asked for; CAP-4 covers the whole argument surface, and the suite pins whole output everywhere; "Next queued story" names a queue with exactly one next entry; the `0-9`/`A-F` clause belongs to the hex generator; `findings.md` is the epic's immutable evidence record. Rejected: 6 low — three whose only fix edits this build's spec or the epic contract (CAP-4's "16 bytes of data", the Code Map's count-0 overstatement, the ALNUM_EIGHT config wording), the contract amendment (arithmetically forced and logged), the sampling breadth (one length rule, pinned across five counts and every pad size), and the `findings.md` line-reference drift.

Follow-up review recommendation: false. Eight patched entries, all low, none high or medium — a first pass needs a patched high, or two or more patched mediums, to justify another pass.

Verification performed (WSL Ubuntu 26.04, GCC 15.2, against Click 2.1 built from upstream master `9197a594b`):
- Pre-fix probes on the baseline reproduced both defects: `RANDALPHANUMSTRING 1` printed `28 | … 00000108 00000008`, and a `RANDHEXSTRING 400` sample contained `47` (`G`) and `67` (`g`).
- Fresh LF export of `df8dff3`: `autoconf && ./configure --with-click && make && make install` — `-W -Wall` clean, `diameter.uo` installed; `g++ -fsyntax-only -W -Wall -Wextra` over every `src/*.cc` produced no output.
- `CLICK=$HOME/click-master/bin/click bats --tap tests` — 44/44 pass, including the five new tests and the retightened `push-avp-rand`.
- AddressSanitizer: package rebuilt and installed into the ASan prefix, full 44-test suite — exit 0, no sanitizer report.
- Manual bytes: `rand-alphanum-one` 32 octets, AVP Length `00000009`, one character and three zero pad octets; `rand-hex-one` AVP Length 9; `rand-num-four`/`rand-alpha-four` AVP Length 12; `rand-hex-alphabet` 10,028 octets, AVP Length `00002718`, message Length `0000272c`, all 16 symbols present.

Residual risks: `linuxmodule` and `bsdpkg` cannot be built on this host, so their compilability rests on the change staying inside one `.cc` file and adding no include. The alphabet test tolerates Click's `expensive Packet::put` advisory (its absence is accepted, any other line fails), and it requires all 16 symbols in 10,000 uniform draws — a miss probability of about 3 × 10⁻²⁹⁰. The generators still draw from `rand()` (F-11, story 6), so a value cannot be reproduced from a seed and the alphabet assertions are statistical rather than deterministic.

