---
title: 'Story 1: Make malformed Diameter input safe'
type: 'bugfix'
created: '2026-11-16'
status: 'done'
review_loop_iteration: 0
followup_review_recommended: true
context: ['{project-root}/AGENTS.md']
warnings: ['oversized']
baseline_revision: 'fc25a03a3f19aa18c5feaf77c40ca31bffbf6adb'
deferred: []
---

<intent-contract>

## Intent

**Problem:** Three elements trust the Diameter header and AVP lengths they are fed: `DiameterPopAVP` loops forever on a zero-length AVP (F-2), `DiameterPopStorePushAVP` overflows its heap buffer on any unpadded AVP body (F-1), `DiameterPushAVP` writes at the offset the header claims instead of at the end of the packet (F-3), and both decapsulators pull past a packet too short to hold their header and forward the leftover (F-6). A hostile or buggy peer can crash, hang, or silently corrupt a graph built from this package today.

**Approach:** Validate before mutating. A short shared guard in `src/diameter.hh` decides whether a packet holds one well-formed Diameter message with well-formed AVP framing; every element calls it first, drops the packet by returning null when it fails, and emits exactly one `click_chatter` line naming the element and the reason. The F-1 body copy is narrowed to the unpadded body it allocates.

## Boundaries & Constraints

**Always:** Drop malformed input — never forward an empty, partial, or repaired packet, and never allocate past a buffer. One warning line per dropped packet, naming the element and the reason; no throttling (log-flood risk from a bad source is accepted). Packets that are well formed keep today's bytes exactly. Tab indentation, `-Wall -Wextra` clean, no new dependency, and all three package targets (userlevel, linuxmodule, bsdpkg) stay compilable, so the shared guard stays free of userlevel-only headers. Element names, arguments, and port counts stay as they are.

**Never:** Add an error output port, change a port count, retry, quarantine, or answer malformed input with a Diameter error message. Do not add a `DiameterHeader` constructor or touch `DiameterEncap` (that is story 2) and do not add AVP padding on encode (story 3). Do not edit the contract files `SPEC.md` and `findings.md`, and do not fix anything outside F-1, F-2, F-3, F-6.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| SHORT_PACKET | 4-octet packet into `DiameterDecap`; 6-octet into `DiameterAvpDecap` | Packet dropped, nothing forwarded | One warning: packet shorter than the header |
| LENGTH_MISMATCH | 20-octet packet, header Length 100, into `DiameterPushAVP` | No byte written past the packet; packet dropped | One warning: header Length vs packet length |
| ZERO_LENGTH_AVP | 32-octet message, trailing AVP length 0, into `DiameterPopAVP` / `DiameterPopStorePushAVP` | Dropped inside the 10 s limit, no hang | One warning: AVP length below its header |
| SHORT_AVP | 32-octet message, AVP length 4, into `DiameterPopAVP` | Dropped, no out-of-bounds read | One warning: AVP length below its header |
| V_SHORT_AVP | 8-octet AVP with V set (header is 12), into `DiameterAvpDecap` | Dropped, 12-octet header never read | One warning: AVP length below its header |
| AVP_PAST_END | 28-octet message, AVP claims length 100, into `DiameterPopAVP` | Dropped, no scan past the message | One warning: AVP extends past the message end |
| NO_AVP | 20-octet header-only message into either pop element | Forwarded unchanged — popping nothing is a no-op, not malformed | No warning |
| UNPADDED_BODY | 44-octet two-AVP message (last AVP length 10) through `DiameterPopStorePushAVP` both ways | 32-octet message out port 0, then the same 44 octets out port 1 | No error, exit 0, no sanitizer report |

</intent-contract>

## Code Map

- `src/diameter.hh` -- `AvpHeader` at line 164 already has a constructor and `getLengthPadded()` (line 218); add `getHeaderLength()` (12 when V is set, else 8), a 20-octet message-length constant, and the shared guards as free inline functions taking raw buffers only (no Click types, keeping the header kernel-buildable).
- `src/diameterpopavp.hh` / `.cc` -- `PORTS_1_1`, `simple_action` at line 28 decodes the header, scans `while(nextAvp < data + dh.getLength())` advancing by `getLengthPadded()` (0 for F-2), then `take`. Scan moves into the shared guard; the pop itself is unchanged.
- `src/diameterpopstorepushavp.hh` / `.cc` -- `1/2` ports, `push()` at line 38 routes on the stored `data`, `simple_action` at line 56 repeats the same scan; lines 76-77 allocate `ah.getLength() - headerLength` and copy `ah.getLengthPadded() - headerLength` (F-1). Stored `AvpHeader ah` is reused when pushing back at lines 87-90.
- `src/diameterpushavp.cc` -- `simple_action` at line 124 puts room first (line 151), then writes at `dh.getLength()` from packet contents (lines 156-171); the offset must be the validated message length, which equals the packet length. `configure` and the RAND* generation are out of scope.
- `src/diameterdecap.cc` -- `simple_action` at line 25 calls `pull(20)` unconditionally. Note `Packet::pull` returns void: it clamps and logs, so the guard must test `length()` first.
- `src/diameteravpdecap.cc` -- `simple_action` at line 25 decodes 8 bytes and pulls 8 or 12 with no length test; `AvpHeader::decode` itself reads 12 bytes when the V bit is set.
- `tests/smoke.bats` -- `run_click` runs a config under a 10 s timeout, `expect` compares the whole output; add a drop assertion helper and one test per new config.
- `tests/configs/` -- valid-path byte assertions that must keep passing (`push-avp`, `pop-avp`, `decap`, `flip-request`, `avp-roundtrip`, `push-avp-rand`).
- `tests/known-defects/` -- repros for F-1, F-2, F-3, F-6 move out of here; `f4-*` and `f7-*` stay because stories 2 and 3 own them.
- `tests/README.md` -- tables naming each config and finding, plus the convention that a fixed repro becomes an asserted config.
- `_bmad-output/specs/spec-diameter-package-hardening/findings.md` -- read-only evidence: repro inputs and the 44-octet two-AVP message at line 152.

## Tasks & Acceptance

**Execution:**
- `src/diameter.hh` -- add the message-length constant, `AvpHeader::getHeaderLength()`, a header guard (packet holds a whole 20-octet header and its Length field equals the packet length) and an AVP-walk guard (each AVP length at least its header, each padded AVP inside the message, walk always advances, V bit read before the 12-octet decode) -- one place decides what malformed means.
- `src/diameterpopavp.cc` -- guard, drop with a warning on failure, forward unchanged when the message has no AVP, otherwise pop exactly as today -- fixes F-2 and the OOB read.
- `src/diameterpopstorepushavp.cc` -- guard both paths, drop with a warning on failure; allocate and copy the unpadded body (`ah.getLength() - headerLength`) in the store path -- fixes F-1.
- `src/diameterpushavp.cc` -- guard before `put()`, drop with a warning on failure, write at the validated message length instead of `dh.getLength()` -- fixes F-3.
- `src/diameterdecap.cc` -- drop packets shorter than 20 octets with a warning; otherwise pull as today -- fixes F-6.
- `src/diameteravpdecap.cc` -- drop packets shorter than 8 octets, and shorter than 12 when the V bit is set, with a warning; otherwise pull the header length -- fixes F-6 for the AVP form.
- `tests/configs/` -- add `malformed-short-packet.click`, `malformed-avpdecap-short.click`, `malformed-avpdecap-v-short.click`, `malformed-zero-length-avp.click`, `malformed-avp-short-length.click`, `malformed-avp-past-message.click`, `malformed-pushavp-length.click`, `malformed-popstorepush-avp-length.click` and `popstorepush-roundtrip.click` (valid two-AVP message, both ports printed) -- the regression set CAP-1 asks for, each derived from its known-defect repro.
- `tests/smoke.bats` -- add a helper asserting exit 0, exactly one drop warning naming the element, and no `Print` line; add one test per new config, plus byte assertions for the round trip -- a forwarded malformed packet or a silent drop fails the run.
- `tests/known-defects/f1-popstorepushavp-overflow.click`, `f2-popavp-zero-length.click`, `f3-pushavp-length-field.click`, `f6-decap-short-packet.click` -- delete, now covered by asserted configs -- the directory keeps only open defects.
- `tests/README.md` -- move those four rows into the `configs/` table and mention the drop warning convention -- the harness documentation matches the tree.

**Acceptance Criteria:**
- Given the eight malformed configs, when each runs under a 10 s timeout, then click exits 0 and prints exactly one warning naming the element and the reason, with no packet reaching `Print`.
- Given `malformed-zero-length-avp.click`, when it runs, then it terminates well inside the timeout instead of hanging (F-2).
- Given `popstorepush-roundtrip.click`, when it runs, then port 0 emits the 32-octet message and port 1 emits the original 44 octets, byte for byte (F-1), with no buffer-overflow abort.
- Given `malformed-pushavp-length.click`, when it runs, then no byte is written past the 20-octet packet and no output line shows a declared length of 112 (F-3).
- Given every malformed and round-trip config, when run against an AddressSanitizer build of Click and this package, then each exits 0 with no sanitizer report.
- Given the six existing `configs/` tests, when `bats --tap tests` runs, then all still pass with unchanged expectations.
- Given the package, when configured and built against upstream Click master, then it compiles with zero warnings at `-Wall -Wextra` and `DiameterPopAVP`, `DiameterPopStorePushAVP`, `DiameterPushAVP`, `DiameterDecap`, `DiameterAvpDecap` keep their names, arguments, and port counts.

## Spec Change Log

## Review Triage Log

### 2026-11-16 — Review pass 1
- verdicts: 42 findings — high 0, medium 15, low 19, false 8, maybe-false 0
- findings:
  - `[low]` `[patch]` smoke.bats preamble still says every expectation records today's bytes — ten tests now assert intended post-fix drops; grouped in entry D (documentation the change made untrue).
  - `[low]` `[patch]` one reason string covers two faults: a buffer too short for the 12-octet V header reports "AVP length below its header" — entry A: split the check and its reason; confirmed by probe (12-octet packet, V set, declared 12 → decapsulated to an empty packet).
  - `[medium]` `[patch]` DiameterAvpDecap never compares the declared AVP length with the packet — entry B: probe `00 00 01 08 00 00 00 04` printed `avp-decap: 0`, i.e. a malformed AVP forwarded as an empty packet; add the declared-length rule to the shared AVP guard.
  - `[medium]` `[patch]` DiameterDecap bypasses the shared guard, contradicting the Approach sentence and the Design Note — entry C: probe (24 octets, Length 100) forwarded `deadbeef` with no warning; add a header-only guard.
  - `[medium]` `[patch]` padding-overhang rule has no test — entry E: probe of a 30-octet message whose AVP declares 9 already drops correctly, so only coverage is missing.
  - `[medium]` `[patch]` only the too-long half of Length equality is tested and the truncated-tail branch is not — entry E: a 24-octet packet declaring 20 passes today's suite untouched.
  - `[medium]` `[patch]` DiameterPopStorePushAVP's armed (data != NULL) drop path is untested — entry E: cover it with a valid message whose 32-octet remainder is truncated to 20 octets before the second pass.
  - `[false]` `[reject]` a malformed packet while armed leaves the stored AVP for the next message — refuted: the stored AVP belongs to the element's 1/2 state across packets, not to the dropped packet; discarding it would change the documented output-1 contract and no test can distinguish the two readings' harm.
  - `[medium]` `[patch]` F-7 and F-4 interactions are undocumented — entry D: the guard now rejects the unpadded AVPs DiameterAvpEncap emits and the invalid Length DiameterEncap emits; both must be named in README until stories 2 and 3 land.
  - `[medium]` `[defer]` the guard indexes packets without ensure_linear — pre-existing: every element already read data()[0..length) linearly before this change, and forcing linearity is a separate concern.
  - `[low]` `[reject]` the guard never checks the Diameter version byte — deliberately omitted: DiameterEncap emits a garbage version until story 2, so requiring 1 would drop the package's own output, and version is outside the intent's malformed classes.
  - `[low]` `[patch]` README claims a package-wide invariant only five elements honour — entry D: scope the sentence to elements that read a received frame (six after entries B, C and F).
  - `[low]` `[patch]` README known-defects paragraph still says the remaining repros abort or hang — entry D: only f4 and f7 remain and both exit 0.
  - `[low]` `[patch]` README smoke paragraph still claims today's bytes "including the wrong ones" — entry D: qualify it to the F-7 expectation.
  - `[low]` `[patch]` the accepted log-flood risk is not written down where users see it — entry D: one sentence in README.
  - `[low]` `[patch]` sprint-status.yaml still says backlog while the story is in review — corrected at finalization (status vocabulary is the file's own: `review`, then `done`).
  - `[false]` `[reject]` the story records no evidence for its acceptance criteria — refuted: step-04 verification is recorded under `## Auto Run Result`, and the pre-fix exit codes are the evidence record in `findings.md`, which the spec marks read-only.
  - `[false]` `[reject]` empty Spec Change Log, Review Triage Log, unexplained `oversized`, pre-set followup flag — refuted: those sections and fields are template-mandated, `oversized` records a spec over the 1600-token aim, and the followup flag is computed at finalization.
  - `[low]` `[reject]` the story's counts say nine new configs while ten ship — real but the only fix edits this build's spec, which triage puts out of bounds; not a code or test defect, and the ASan pass covered all sixteen configs.
  - `[low]` `[reject]` the I/O matrix paraphrases the warning strings instead of quoting them — same reason: the fix would edit this build's spec; the exact strings are pinned by `smoke.bats` and `diameter_check_reason()`.
  - `[low]` `[patch]` `static const uint32_t` wire sizes in a header give each translation unit a copy — entry A: make them an enum.
  - `[low]` `[patch]` the V-bit header length lives in three places — entry A: one helper computes it for the guard, the walk and the element.
  - `[low]` `[reject]` the drop boilerplate is repeated five times and `class_name()` does not identify the instance — a shared helper would need Click types in the header or a new file; the format is pinned by the tests, and `class_name()` is stable where `name()` may be empty.
  - `[low]` `[patch]` the comment in malformed-avp-past-message.click says the scan "never leaves the packet" — entry D: wording means the opposite; also noted the `timeout` fallback and the one-test-per-config remark, which need no change (CI and the documented recipe provide coreutils; every config has a test).
  - `[medium]` `[patch]` (edge) DiameterDecap decapsulates a Length-mismatched frame — same defect as entry C.
  - `[medium]` `[patch]` (edge) DiameterAvpDecap accepts a declared length below the header or past the packet — same defect as entry B.
  - `[false]` `[reject]` (edge) a malformed packet while armed leaks the stored buffer and appends a stale AVP — refuted as above: the buffer is freed on the next successful push-back, and the state is the element's own contract.
  - `[medium]` `[patch]` (edge) the Approach sentence claims every element calls the guard first — entry C: made true for the readers by guarding DiameterDecap and DiameterFlipRequest.
  - `[medium]` `[patch]` (verification gap) Length equality is only tested in the too-long direction — entry E: add a config with 24 octets declaring 20; the reviewer showed the natural `declared > length` edit keeps the whole suite green.
  - `[medium]` `[patch]` (verification gap) the padding-overhang rule the Design Notes single out has no config — entry E: add the 30-octet message.
  - `[medium]` `[patch]` (verification gap) DiameterFlipRequest decodes and re-encodes 20 octets of any packet — entry F: a 4-octet packet probes to 16 octets read and written past the packet length; guard it and document.
  - `[false]` `[reject]` (intent) the sanitizer surface is only asserted by proxy — refuted: verification is performed by the workflow, not shipped in the diff; the ASan run covered all sixteen configs and was clean.
  - `[false]` `[reject]` (intent) "reproduce first, capture the failing exit code" has no artifact — refuted: `findings.md` carries the pre-fix exit codes (134, 124, the 112-octet declared length, `pull 20 > length 4`) and is the evidence record this spec marks read-only.
  - `[low]` `[reject]` (intent) the log surface is over-pinned at byte equality — that is the point of a pinned expectation; loose matching loses the reason discrimination the story requires.
  - `[low]` `[patch]` (intent) the reason taxonomy collapses at the V-bit boundary — same defect as entry A.
  - `[false]` `[reject]` (intent) Length equality is stricter than the dispatch's "beyond the packet" — refuted: accepting a shorter Length forces the writer to extend the field over trailing bytes, which the spec forbids repairing; the Design Notes record the choice.
  - `[medium]` `[patch]` (intent) declared lengths are enforced at the message walk but absent at DiameterDecap and partial at DiameterAvpDecap — same defects as entries B and C.
  - `[medium]` `[patch]` (intent) DiameterFlipRequest is left unguarded while the README claims the whole graph is safe — same defect as entry F.
  - `[low]` `[reject]` (intent) the F-1 byte-for-byte assertion cannot see padding regeneration — true but F-7 owns padding; the fixture's zero padding is what story 3 will re-check.
  - `[low]` `[reject]` (intent) the no-AVP rule is exercised on one of its two paths — the armed path needs a packet whose Length is rewritten mid-graph, which no current element can do; the three lines are shared with the round-trip test.
  - `[false]` `[reject]` (intent) the README readiness claim rests on a sanitizer pass the diff does not contain — refuted: the pass is workflow verification, not a shipped file.
  - `[low]` `[reject]` (intent) the liveness and log surfaces depend on `timeout(1)` and on bats merging stderr — both hold on the CI image and in the documented recipe; failing loudly without `timeout` would break local runs for no gain.

## Design Notes

- **Length equality is the malformed test.** These elements receive exactly one Diameter message per packet (`DiameterDecap` pulls the 20-octet header off the front), so a Length field that disagrees with the packet length in either direction means the frame cannot be trusted; appending at the packet end while the field says something shorter would emit trailing junk inside the declared message. Equality is therefore required by all three header-reading elements, and it is what makes F-3's offset safe without a second bounds check.
- **The guard must reject padding overhang.** An AVP whose unpadded length fits but whose padded length does not (message 30 octets, AVP length 9 at offset 20) must be rejected, or the pop paths would `take` more than the message and leave a Length below 20.
- **No `put()`-failure guard.** Allocation failure on `put()` is not a malformed-input path, has no repro, and is out of this story's scope.
- **No-AVP messages are legal.** They are a no-op for both pop elements; today `DiameterPopStorePushAVP` reads past the packet in that case, and forwarding unchanged replaces that read.
- **`findings.md` stays as written** — it is the evidence record behind the epic, not a status board; the story spec and `tests/` carry the outcome.

## Verification

**Commands:**
- `git archive HEAD | tar -x -C $HOME/src/pkg-story1` (in WSL, LF tree) then `autoconf && ./configure --with-click=$HOME/click-master --prefix=$HOME/click-master && make && make install` -- expected: builds with zero warnings, installs `diameter.uo`.
- `CLICK=$HOME/click-master/bin/click bats --tap tests` -- expected: every test passes; if bats-core is unavailable, run each config under `timeout 10` and compare by hand against the same expectations.
- ASan pass: build Click from the same source into `$HOME/click-asan` with `CXXFLAGS="-fsanitize=address -g"`/`LDFLAGS="-fsanitize=address"`, install the package into that prefix, and run the nine new configs plus `tests/configs/` -- expected: exit 0, no sanitizer report.

**Manual checks (if no CLI):**
- Read each drop warning in the captured output and confirm it names the element and the reason, one line per dropped packet.

## Auto Run Result

Summary: every element that reads a received Diameter frame now validates it before touching it and drops what it cannot trust. `src/diameter.hh` gains the wire sizes, a validation checklist and four free inline guards — `diameter_check_header()` (a whole 20-octet header whose Length equals the packet), `diameter_check_avp()` (the V bit decides an 8- or 12-octet header, the declared length must be at least that header and at most the available octets), and `diameter_check_message()` (the header rule plus a walk whose padded AVPs stay inside the message, always advancing). `DiameterPopAVP`, `DiameterPopStorePushAVP`, `DiameterPushAVP`, `DiameterDecap`, `DiameterAvpDecap` and `DiameterFlipRequest` call the guard first, drop with one `ELEMENT: dropping malformed packet: REASON` line, and keep their names, arguments and port counts. F-1 is fixed by allocating and copying the unpadded body, F-2 by a walk that always advances by at least a header, F-3 by writing at the validated packet length instead of the header's own field, F-6 by testing the length before pulling.

Files changed:
- `src/diameter.hh` — wire sizes as an enum, `AvpHeader::getHeaderLength()`, and the four validation guards.
- `src/diameterpopavp.cc` — guard, drop, forward unchanged when the message has no AVP, then pop the validated offset.
- `src/diameterpopstorepushavp.cc` — guard both paths; store and copy the unpadded body; append at the validated message length.
- `src/diameterpushavp.cc` — guard before `put()`, append at the validated message length.
- `src/diameterdecap.cc`, `src/diameteravpdecap.cc`, `src/diameterfliprequest.cc` — header or AVP guard before mutating, drop with the shared warning.
- `tests/smoke.bats` — `expect_drop` helper plus sixteen new tests (23 total).
- `tests/configs/` — fifteen new configs: the round trip, the no-AVP no-op, and thirteen malformed cases.
- `tests/known-defects/` — F-1, F-2, F-3 and F-6 repros removed; F-4 and F-7 stay.
- `README.md`, `tests/README.md` — the drop contract, which elements validate, the accepted log-flood risk, and the F-4/F-7 interactions the guard exposes.

Review findings breakdown: 42 findings — 25 patched, 1 deferred, 16 rejected (8 false, 8 low not worth the complexity). Patched by entry verdict: high 0, medium 4, low 4. Fixes applied: the V-header case got its own reason; one AVP guard now serves `DiameterAvpDecap` and the message walk; `DiameterDecap` validates the header it strips without walking AVPs; `DiameterFlipRequest` is guarded; coverage added for Length-short, padding overhang, trailing octets, decap Length mismatch, AVP declared length, flip on a short packet and the armed drop path; README and tests documentation corrected. Deferred: linear access for packets held in several buffers (pre-existing; every element already read `data()[0..length)` linearly). Rejected highlights: a stale stored AVP after a drop (the state is the element's cross-packet contract, not the packet's), a version-byte check (would drop `DiameterEncap`'s output until story 2), the story's own count and matrix wording (fixing them would edit this build's spec), and the review layers' duplicate readings of the sanitizer and log surfaces.

Follow-up review recommendation: true. Named unverified risk: the guard now rejects the package's own encoder output until F-4 and F-7 land, so an `DiameterEncap` → `DiameterDecap` or `DiameterAvpEncap` → `DiameterAvpDecap` chain drops where it used to forward; that interaction is documented and reasoned, but no test exercises a chain that mixes a writer with a reader.

Verification performed (independent of the implementation pass, on WSL Ubuntu 26.04, GCC 15.2, against the installed Click 2.1 prefix built from the baseline tree named in `SPEC.md`):
- `autoconf && ./configure --with-click && make && make install` from an LF export of the tree — zero warnings.
- `g++ -fsyntax-only -Wall -Wextra` over every `src/*.cc` — zero warnings.
- `CLICK=.../bin/click bats --tap tests` — 23/23 pass, including the six pre-existing expectations unchanged.
- AddressSanitizer: Click rebuilt with `-fsanitize=address` (confirmed linking `libasan`), package rebuilt against it, all 23 configs run — exit 0, no sanitizer report.
- Triage probes before patching confirmed each accepted finding: `DiameterAvpDecap` forwarded an empty packet for a declared length of 4, `DiameterDecap` forwarded four octets of a Length-mismatched frame, `DiameterFlipRequest` accepted 4 octets.

Residual risks: `linuxmodule` and `bsdpkg` targets cannot be built on this host (no kernel headers, no BSD), so their compilability is reasoned from the guard using only `<stdint.h>` and no userlevel-only headers; the guard assumes each packet's Diameter frame is contiguous, which was already true of every element before this change.

