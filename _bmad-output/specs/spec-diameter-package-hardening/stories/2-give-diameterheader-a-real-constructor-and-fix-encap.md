---
title: 'Story 2: Give DiameterHeader a real constructor and fix Encap'
type: 'bugfix'
created: '2026-11-16'
status: 'done'
review_loop_iteration: 0
followup_review_recommended: false
context: ['{project-root}/AGENTS.md']
warnings: ['oversized']
deferred:
  - summary: >-
      Diameter Length is a 24-bit field, so an Encap payload above 16,777,195 octets truncates it and produces a frame the package's own guards reject.
    evidence: |-
      DiameterHeader::encode writes only three octets; the truncation predates this story. No Click source in the tree produces such a packet and the intent sets no length-limit policy, so a guard would be new behaviour.
    location: >-
      src/diameterencap.cc:60
    severity: low
  - summary: >-
      A failed Packet::push() in DiameterEncap is dereferenced by dh.encode(wp->data()).
    evidence: |-
      push() returns null on allocation or uniqueify failure and the element never checks it. Pre-existing: the call and the unchecked dereference predate this story, and no test can reach it.
    location: >-
      src/diameterencap.cc:62
    severity: low
baseline_revision: '6a4df9f761b969ccc304fd1485b5cc18b7b78a68'
---

<intent-contract>

## Intent

**Problem:** `DiameterHeader` (`src/diameter.hh:23`) has no constructor, so version, Length, flags, code and App-Id are whatever the stack held. `DiameterEncap` sets only its argument fields and writes the payload length into Length, so its output carries a garbage version byte (`0x2a`, `0xde` observed) and a Length 16 octets short. Neither another implementation nor story 1's guard accepts it.

**Approach:** Initialize every field in a constructor (version 1, Length 20, flags off, identifiers 0), move the wire-size enum above the class so one constant serves constructor and elements, and have `DiameterEncap` write Length = 20 + payload length.

## Boundaries & Constraints

**Always:** Version 1; Length counts the 20-octet header plus all payload octets; every field initialized before any encode; `src/diameter.hh` stays free of Click and C++-runtime headers so `linuxmodule` and `bsdpkg` compile; tabs, zero warnings at `-Wall -Wextra`; element names, arguments, ports and existing configs unchanged.

**Never:** No AVP padding (story 3), no RAND or seeding changes (stories 4, 6), no P/E/T policy (story 5), no include-guard, `<iostream>`, `AC_INIT` or fork work (story 8). Do not edit `SPEC.md` or `findings.md`. Do not make `hbh`/`e2e` deterministic — `rand()` is story 6's.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| ENCAP_PAYLOAD | 4-octet `deadbeef` into `DiameterEncap(CODE 280, REQUEST true)` | 24 octets: `01000018 80000118 <hbh> <e2e> deadbeef` | No error expected |
| ENCAP_EMPTY | `InfiniteSource(LENGTH 0)` into `DiameterEncap` | 20 octets: `01000014` then flags, code, App-Id, identifiers | No error expected |
| ENCAP_DECAP_CHAIN | 4-octet payload through `DiameterEncap` then `DiameterDecap` | `deadbeef` forwarded, exit 0, no drop warning | No error expected |
| RATED_SOURCE | `DiameterRatedSource(CODE 280, REQUEST true, LIMIT 1)` | 20 octets, version 1, Length 20, flags `80`, code `000118` | No error expected |
| REPEATED_RUNS | The same Encap config run twice | Version, Length, flags, code, App-Id identical; `hbh`/`e2e` may differ (F-11) | No error expected |

</intent-contract>

## Code Map

- `src/diameter.hh:23-162` -- `DiameterHeader`: nine fields, `decode`/`encode`, no constructor; mirror `AvpHeader` (`:173-176`).
- `src/diameter.hh:268-272` -- wire-size enum sits after both classes; move it above `DiameterHeader` for `DIAMETER_MESSAGE_HEADER_LENGTH`.
- `src/diameterencap.cc:56-66` -- `setLength(p_in->length())` at 60 is the defect; `push(20)` at 62; `configure` (25-54) never sets version.
- `src/diameterencap.hh:36` -- `dh` member is default-constructed once, so the constructor is what gives `configure` a version.
- `src/diameterratedsource.cc:68-72` -- already version 1 and Length 20; `rand()` fills `hbh`/`e2e` (109-110, 140-141); encodes at 118 and 150.
- `src/diameterpushavp.cc:165-183` -- `decode()`s all 20 octets before `encode()`, so no change needed; same in `diameterfliprequest.cc:39-42`, `diameterpopavp.cc:47-56`, `diameterpopstorepushavp.cc:69-99`.
- `tests/known-defects/f4-encap-header.click` -- the repro to promote; `f7-avp-padding.click` stays.
- `tests/smoke.bats:41-78` -- `expect` compares whole output; random bytes need the regex form at 47-52; `run_click` has a 10 s timeout.
- `tests/README.md:33-86`, `README.md:185-215` -- F-4 tables and passages to correct.
- `findings.md:29-35` -- read-only F-4 evidence.

## Tasks & Acceptance

**Execution:**
- `src/diameter.hh` -- move the enum above the class; construct with version 1, Length `DIAMETER_MESSAGE_HEADER_LENGTH`, flags false, code/App-Id/`hbh`/`e2e` 0 -- an uninitialized header becomes unrepresentable.
- `src/diameterencap.cc` -- Length `DIAMETER_MESSAGE_HEADER_LENGTH + p_in->length()`, push `DIAMETER_MESSAGE_HEADER_LENGTH` -- fixes F-4's Length.
- `src/diameterratedsource.cc` -- replace literal 20 with the constant, keeping `setVersion(1)` explicit -- the generator states its own wire size.
- `tests/configs/encap.click`, `encap-decap.click`, `rated-source.click` -- payload encap, the encap-then-decap chain, one generated message -- CAP-2 byte assertions.
- `tests/smoke.bats` -- three tests: regex the random identifiers, exact-assert the rest -- a version or Length regression fails the run.
- `tests/known-defects/f4-encap-header.click` -- delete -- the directory keeps only open defects.
- `tests/README.md`, `README.md` -- move the F-4 row into `configs/`, drop the known-defect row, correct the two passages -- docs match the fixed tree.

**Acceptance Criteria:**
- Given a 4-octet payload, when `DiameterEncap` runs, then the packet is 24 octets beginning `01000018 80000118`, `hbh`/`e2e` 8 hex digits each (CAP-2).
- Given a zero-octet packet, when `DiameterEncap` runs, then the packet is 20 octets beginning `01000014`.
- Given `DiameterEncap` then `DiameterDecap`, when a 4-octet payload passes, then it comes out unchanged with no drop warning.
- Given `DiameterRatedSource` `LIMIT 1`, when it emits, then the message is version 1, Length 20, flags `80`, code `000118` (initialized flags; RFC flag policy stays story 5).
- Given the same Encap config twice, when outputs are compared, then version, Length, flags, code and App-Id agree byte for byte.
- Given a build against Click master at `-Wall -Wextra`, then zero warnings, all tests pass, and `tests/known-defects/` holds only `f7-avp-padding.click`.

## Spec Change Log

## Review Triage Log

### 2026-11-16 — Review pass
- verdicts: 23 findings — high 0, medium 2, low 18, false 3, maybe-false 0
- findings:
  - `[low]` `[patch]` `sprint-status.yaml` still says `backlog` while the story spec is in progress — real; the tracking file is the repo's status source, corrected at finalization to `done`.
  - `[low]` `[reject]` the I/O matrix byte strings omit App-Id (`01000018 80000118 <hbh> <e2e> deadbeef` is 20 octets) — real, and the tests do assert the `00000000` slot; the only fix edits this build's spec, which triage excludes.
  - `[low]` `[reject]` Verification never names `-Wall -Wextra` — the strict pass ran with `-W -Wall -Wextra -Werror` and is recorded in the result; wording it into the spec is a spec edit.
  - `[false]` `[reject]` Verification carries no observed results — refuted: outcomes belong in `## Auto Run Result`, which finalization writes for every command in that section.
  - `[low]` `[patch]` the constant substitution is partial — real: `DiameterHeader::encode` zeroes a literal 20 and `DiameterRatedSource::setup_packet` sizes its packet with literals; both now use `DIAMETER_MESSAGE_HEADER_LENGTH`. `AvpHeader`'s 8/12 pair is the V-bit header rule, not the message header, and stays.
  - `[low]` `[defer]` Length is a 24-bit field, so a payload above 16,777,195 octets truncates — real but pre-existing: `encode` always truncated, no Click source in the tree produces such a packet, and adding a guard is policy the intent does not set; recorded in `deferred`.
  - `[medium]` `[patch]` the Design Notes' claim that the guard used to reject Encap output at the pop and push elements was exercised only through Decap — real verification gap; `encap-push-pop.click` now runs Encap → PushAVP → PopAVP.
  - `[low]` `[patch]` App-Id is only ever asserted as zero and no config sets `APPID` — real; `rated-source.click` now sets `APPID 42` and the test expects `0000002a`. The answer/flag surface stays story 5's by design.
  - `[low]` `[reject]` the pre-fix probe version bytes are not reproducible — expected: they come from uninitialized memory, which is the defect; the reproducible evidence is `Length == 4` and the guard's drop. Correcting the wording is a spec edit.
  - `[false]` `[reject]` `findings.md` still lists F-4 as high — refuted: the epic designates that file as the immutable evidence record, not a status board (story 1's Design Notes); story spec, tests and README carry the outcome.
  - `[low]` `[patch]` the README sentence "once they are framed in a message until F-7 pads them" now dangles — real: it lost the F-4 contrast; rewritten as one statement.
  - `[low]` `[patch]` the Known-limitations flag bullet leads with fixed behaviour and drops the RFC reason — rewritten to state the remaining policy gap (P on an answer, RFC 6733 §3) and keep initialization as context.
  - `[low]` `[patch]` `tests/README.md` and the `smoke.bats` header still claim every test pins exact bytes — real: the new tests regex random octets and one runs its config twice; both headers now describe that.
  - `[low]` `[patch]` `encap.click`'s two independent sources make its test depend on task order — real fragility; split into `encap.click` (payload) and `encap-empty.click` (empty packet), so neither test depends on scheduling.
  - `[low]` `[reject]` the repeated-run check cannot tell random identifiers from frozen ones — true and harmless: the row claims only the non-random fields, and frozen identifiers would be F-11's defect, not a regression this story can cause.
  - `[low]` `[reject]` Boundaries say existing configs are unchanged while the F-4 repro is deleted — the deletion is a Task of the same spec, and a known-defect repro is not one of the "existing configs" the boundary protects; the wording fix is a spec edit.
  - `[low]` `[reject]` the Code Map mixes pre- and post-change line anchors — real; they are baseline-relative and were accurate when the implementer used them. Refreshing them is a spec edit.
  - `[low]` `[patch]` the `encap.click` row reads "Length 20 and 24" as two lengths for one packet — reworded to say Length counts the header plus payload.
  - `[low]` `[defer]` (edge) a payload past 24 bits truncates the Length field — same defect as the truncation row above; shared route.
  - `[low]` `[defer]` (edge) a failed `p_in->push()` dereferences null at `dh.encode(wp->data())` — real but pre-existing: both calls predate this story and Click fails push only on allocation failure; recorded in `deferred`.
  - `[low]` `[patch]` (edge) the claim that one constant serves constructor and elements — same as the partial-substitution row; shared route.
  - `[medium]` `[patch]` (intent) `DiameterPushAVP`, which the intent names, is not exercised by any new test — real: the file is untouched and its guard acceptance rested on code reading; covered by `encap-push-pop.click`.
  - `[false]` `[reject]` (intent) CAP-2's "identical header bytes across repeated runs" is narrowed to the non-random fields — refuted: CAP-6 assigns seeded reproducibility to story 6 and this story forbids making `hbh`/`e2e` deterministic, so the corpus selects the narrowed reading.

## Design Notes

- **Version 1 belongs in the constructor.** Every writer either relies on defaults (`DiameterEncap::configure` never sets version) or decodes all 20 octets before re-encoding, so a default of 1 fixes the defect without touching those paths.
- **Length equality makes the chain work.** RFC 6733 §3 counts the header, and story 1's guard requires Length == packet length, so Encap output was rejected by the pop, push and decap elements. `encap-decap.click` pins that and closes the unverified risk story 1's review named.
- **Identifiers stay random.** `hbh`/`e2e` come from `rand()` (F-11), so CAP-2's repeated-run identity is asserted for the fields that are not deliberately random; forcing determinism here would take story 6's change and remove per-message variation.
- **`DiameterRatedSource` keeps explicit version and Length** although the constructor supplies both: a generator emitting a fixed 20-octet message should say so, and its test asserts it.
- **Flag defaults are initialization, not policy.** Zeroing the three flags also removes F-5's `e0` byte from generated messages; story 5 still owns which flags a request or answer may carry, and `DiameterFlipRequest`'s P rule.
- **Pre-fix probes** on the installed package (`click-master`, 2026-11-16): 4-octet payload → `24 | ac000004 80000118 ... deadbeef`; empty packet → `20 | 92000000 ...`; Encap→Decap drops on `header Length does not match packet length`; RatedSource → `20 | 01000014 e0000118 ...`. Reproduce these before editing.

## Verification

**Commands:**
- Export the working tree to WSL with LF endings; `autoconf && ./configure --with-click=$HOME/click-master --prefix=$HOME/click-master && make && make install` -- expected: zero warnings, `diameter.uo` installed.
- `CLICK=$HOME/click-master/bin/click bats --tap tests` -- expected: every test passes, including the three new configs.
- Rebuild Click into `$HOME/click-asan` with ASan, install the package there, run every config -- expected: exit 0, no sanitizer report.

## Auto Run Result

Summary: `DiameterHeader` now initializes every field in a constructor (version 1, Length 20, flags clear, code, App-Id and both identifiers 0), and the wire-size enum moved above it so one constant serves the class, `DiameterEncap` and `DiameterRatedSource`. `DiameterEncap` writes Length as the 20-octet header plus the payload, so its frames satisfy story 1's guards and another implementation's Length check, and `DiameterRatedSource`'s flags come out initialized instead of garbage. The F-4 repro became an asserted config, and an Encap → PushAVP → PopAVP chain pins the writer/reader interaction story 1's review left unverified.

Files changed:
- `src/diameter.hh` — enum hoisted above the class, `DiameterHeader` constructor, `encode` zeroes the constant length.
- `src/diameterencap.cc` — whole-message Length and a constant header push.
- `src/diameterratedsource.cc` — the constant replaces both literal 20s in `configure` and `setup_packet`.
- `tests/configs/` — `encap.click`, `encap-empty.click`, `encap-decap.click`, `encap-push-pop.click`, `rated-source.click`.
- `tests/smoke.bats` — five tests plus header notes on the regex and repeated-run conventions.
- `tests/known-defects/f4-encap-header.click` — deleted; only F-7's repro remains.
- `tests/README.md`, `README.md` — F-4 removed from the defect lists; the flag bullet states the remaining policy gap.

Review findings breakdown: 23 findings — high 0, medium 2, low 18, false 3, maybe-false 0. Patched: 11 rows in 9 entries (1 medium, 8 low) — constant substitution, chain coverage for PushAVP and PopAVP, a non-zero App-Id, the config split that removed a task-order dependency, and README/tests wording. Deferred: 2 (the 24-bit Length truncation, pre-existing; the unchecked `push()` in `DiameterEncap`, pre-existing). Rejected: 9 — fixes that would edit this build's spec (matrix byte string, `-Wall -Wextra` wording, probe reproducibility, Boundaries wording, Code Map anchors), refuted claims (observed results belong in this section; `findings.md` is the epic's immutable evidence record; CAP-6 selects the narrowed repeated-run reading), and one no-harm claim about what the repeated-run comparison can distinguish.

Follow-up review recommendation: false. Only one patched entry was medium and none was high; a first pass needs two or more patched medium entries, so the work has converged.

Verification performed (WSL Ubuntu 26.04, GCC 15.2, against the installed Click 2.1 prefix built from upstream master 9197a594b):
- Pre-fix probes reproduced the defect: Encap emitted `ac000004` and `92000000` (garbage version, Length = payload), and Encap → Decap dropped on `header Length does not match packet length`.
- Fresh LF export: `autoconf && ./configure --with-click && make && make install` — zero warnings.
- `make CXXFLAGS="-g -O2 -fPIC -W -Wall -Wextra -Werror"` — clean.
- `CLICK=.../bin/click bats --tap tests` — 28/28 pass, including the five new tests and the 23 unchanged ones.
- AddressSanitizer: Click relinked with `libasan` (confirmed by `ldd`), package rebuilt and installed into that prefix, all 28 configs run — exit 0, no sanitizer report.

Residual risks: `linuxmodule` and `bsdpkg` cannot be built on this host, so their compilability rests on the header gaining no includes. `hbh`/`e2e` stay time-seeded random (F-11) until story 6, so only the deterministic header fields can be compared across runs. Encap output whose payload is not well-formed AVP framing is still dropped by `DiameterPushAVP` and `DiameterPopAVP`, which is why the chain config uses an AVP-shaped payload. `DiameterAvpEncap` still emits unpadded AVPs (F-7, story 3).
