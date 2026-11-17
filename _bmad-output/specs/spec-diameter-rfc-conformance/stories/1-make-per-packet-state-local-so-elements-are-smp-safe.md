---
title: 'Make per-packet state local so elements are SMP-safe'
type: 'refactor'
created: '2026-11-17'
status: 'done'
baseline_revision: '5af853c614ff00eecfc4733ed8716af54ebae15d'
review_loop_iteration: 1
followup_review_recommended: false
context: ['{project-root}/AGENTS.md']
warnings: []
deferred:
  - summary: >-
      DiameterPopStorePushAVP is a fourth push writer that still keeps per-packet state in a member.
    evidence: |-
      src/diameterpopstorepushavp.cc decodes, mutates and encodes the member AvpHeader inside push(), the same shape as the three elements this story fixed, so two threads can interleave ah.decode/ah.encode and corrupt the appended header. Finding A-8 and this story's contract both list only the three writers, so it is out of scope and needs its own story.
    location: >-
      src/diameterpopstorepushavp.cc:69
    severity: medium
  - summary: >-
      The A-8 repro line in findings.md and the story-1 invoke_dev_with text in stories.yaml still say `click -t 2` and still offer a frame-level assertion as an alternative to ThreadSanitizer.
    evidence: |-
      -t is --time in Click, so the command prints timings and stays single threaded, and the frame-level assertion was measured to pass on the racy package. Both files are queue artifacts outside this story's change set.
    location: >-
      _bmad-output/specs/spec-diameter-rfc-conformance/findings.md:144
    severity: low
  - summary: >-
      No config-only mechanism asserts that the producers really landed on two router threads.
    evidence: |-
      Click exposes no task-to-thread query to a config, and StaticThreadSched only warns when a preference is out of range. The tests fail on a rejected preference and skip on a single-threaded Click, but deleting the StaticThreadSched line from a config would still pass on a multithread Click. Would be settled by a thread-assignment readout element or handler.
    location: >-
      tests/configs/smp-encap.click:17
    severity: low
  - summary: >-
      DiameterEncap and DiameterAvpEncap do not check whether push() or put() returned null before writing the header.
    evidence: |-
      src/diameteravpencap.cc writes through wp->data() after p_in->push() and wp->put() without a null check, and src/diameterencap.cc does the same after p_in->push(). Pre-existing: the package at 5af853c has the same shape, so this story did not introduce it; a packet-growth failure would crash the router instead of dropping the packet.
    location: >-
      src/diameteravpencap.cc:57
    severity: low
---

<intent-contract>

## Intent

**Problem:** `DiameterEncap`, `DiameterAvpEncap` and `DiameterPushAVP` keep per-packet state in element members (`dh`, `ah`, `datauint`, `datastring`) and rewrite them inside `simple_action()`. Click does not serialise a push element across router threads, so two packets can interleave between `ah.setLength(...)` and `ah.encode(...)` and one frame is stamped with the other packet's AVP length; `DiameterPushAVP` additionally reassigns a shared `String` per packet. Single-threaded output is correct, which is why the whole existing suite passes (finding A-8, CAP-5).

**Approach:** Treat the members as configuration only and build the header and value state for each packet in locals at the top of `simple_action()`, so no packet touches shared mutable element state. No argument, byte or documentation change.

## Boundaries & Constraints

**Always:** Single-threaded output stays byte-identical, including the seeded `RandomSeed` runs; the order and count of `click_random()` calls stays exactly as today, because those tests pin the drawn octets; configuration values stay in members; tabs for indentation; the package stays warning-free at `-Wall -Wextra`.

**Never:** No new or changed arguments (`MANDATORY`, `UINT32 0` and the conflicting-value check belong to stories 2 through 5), no new validation or drop reasons (stories 2, 6, 7 and 8), no lock, semaphore or `Spinlock` around `simple_action()` (a push element must not block), no edit to `DiameterRatedSource`, whose identifiers, code range and header handling belong to stories 8 and 9, and no change to `.github/workflows/` (SPEC non-goal: no CI pipeline work).

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Single-threaded encode | any existing `tests/configs/` packet | bytes identical to the pre-change build | No error expected |
| Two threads, one element | two `DiameterRatedSource` elements placed on two router threads (`-j 2`, `StaticThreadSched`) into one `DiameterPushAVP` | every frame is 36 octets (20-octet message plus a 16-octet AVP), header Length 0x24, AVP Length 0x10, eight hex value octets | No error expected |
| Click without multithread support | the same config, a Click built without `--enable-user-multithread` | test skips with a reason instead of passing on a single thread | Skip, not failure |
| Configured value, unchanged | `OCTETSTRING "abc"`, `RANDUINT32`, `RAND*STRING n` | same value, length and random draw order as before the change | No error expected |
| Malformed message | `malformed-pushavp-length.click` and siblings | unchanged single drop warning naming the element and reason | Warning line, no output packet |

</intent-contract>

## Code Map

- `src/diameterencap.cc:54-64` -- `simple_action()` mutates the member `dh` (`setHbh`, `setE2e`, `setLength`) and then encodes it; the member is declared at `src/diameterencap.hh:89` and filled by `configure()` at `:44-49`.
- `src/diameteravpencap.cc:43-61` -- `simple_action()` writes `ah.setLength()` and reads `ah.getLengthPadded()`/`getHeaderLength()` from the shared member declared at `src/diameteravpencap.hh:71`; `configure()` at `:27-38` fills it.
- `src/diameterpushavp.cc:110-172` -- `simple_action()` assigns `datauint` (`:123`) and `datastring` (`:127-139`) per packet, then `ah.setLength()` (`:156`) and `ah.encode()` (`:157`); members at `src/diameterpushavp.hh:119-126`.
- `src/diameter.hh:18-170` -- `DiameterHeader`, trivially copyable, every field initialised; `:172-274` `AvpHeader`, same. `getHeaderLength()`/`getLengthPadded()` read only `vendorSpecific`/`length`.
- `src/diameter.hh:318-396` -- `diameter_check_header()`/`diameter_check_message()` are pure functions over the packet buffer; the append path already validates before mutating, so the local-state change is confined to the writer half of `simple_action()`.
- `tests/smoke.bats:1-40` -- `run_click`/`run_config` helpers and the `click=${CLICK:-click}` contract; a two-thread test needs its own helper that passes `-j N`.
- `tests/configs/encap-push-pop.click` and `tests/configs/randomness-push-avp.click` -- the two configs that pin a PushAVP append and its seeded value; read them before changing `simple_action()` so the value precedence stays exact.
- `tests/README.md` -- how a config is named, commented and listed.
- `src/diameterratedsource.cc:85-141` -- read-only evidence: it mutates its own `dh`, but it is one task on one thread with one output port, and this story does not touch it.

## Tasks & Acceptance

**Execution:**
- `src/diameterencap.cc` -- copy `dh` into a local `DiameterHeader` at the top of `simple_action()`, set hop-by-hop, end-to-end and Length on the local, and encode the local -- removes the three shared writes while keeping `configure()`'s flags.
- `src/diameterencap.hh` -- comment the `dh` member as configuration only, never written per packet -- stops the next reader from reintroducing the race; no interface change.
- `src/diameteravpencap.cc` -- copy `ah` into a local `AvpHeader`, derive `headerLength`, padded length and padding from the local, encode the local -- the length and the header now always belong to the same packet.
- `src/diameteravpencap.hh` -- comment the `ah` member as configuration only -- same reason as above.
- `src/diameterpushavp.cc` -- build local `AvpHeader`, `String` and `uint32_t` copies; keep the existing `if`/`else if` chain, its `click_random()` call order and the `datastring.length() > 0 ? datastring.length() : (datauint > 0 ? 4 : 0)` length rule, but apply every write to the locals -- identical bytes, no shared mutation.
- `src/diameterpushavp.hh` -- comment the members as configuration only -- same reason as above.
- `tests/configs/smp-push-avp.click` -- two `DiameterRatedSource` elements on two threads (`RATE 100000`, `LIMIT 50`, `STOP true`, `StaticThreadSched`) into one `DiameterPushAVP(CODE 264, RANDHEXSTRING 8)` into `Print(..., MAXLENGTH 200, CONTENTS HEX)` into `Discard`, with a **different Command Code per source** (`280` and `281`) so the output says which source produced each frame -- this is a shape check, not a race detector: the appended AVP Length is fixed by configuration, so no interleaving can change it.
- `tests/configs/smp-encap.click` -- two threads, two `InfiniteSource` elements emitting **different payload lengths** (4 and 8 octets) into one `DiameterEncap(CODE 280, REQUEST true)` into `Print` into `Discard` -- the shared header's Length is derived from each packet here, so a cross-thread write makes the declared Length disagree with the printed frame size, which the test can see. `DiameterRatedSource` cannot serve: it always emits the same 20-octet header and takes no `DATA`.
- `tests/configs/smp-avpencap.click` -- the same two payload lengths from two `InfiniteSource` elements into one `DiameterAvpEncap(CODE 264)` into `Print` into `Discard` -- the AVP Length and its padding are derived per packet, so a cross-thread write shows as an AVP Length that disagrees with the value octets printed.
- `tests/smoke.bats` -- add `run_click_threads N CONFIG` and one test per `smp-*` config. Skip only when the run otherwise succeeded and Click printed the no-multithread warning (test the exit status before skipping). Pin generated value octets to the generator's alphabet (`(3[0-9]|4[1-6]){4}` per four octets) instead of `[0-9a-f]`, require both source markers to appear, and require a frame floor above one source's `LIMIT`.
- `tests/README.md` -- list the three configs and state what each one proves and what it does not; ThreadSanitizer, not the frame assertions, is what detects the shared-`String` class in `DiameterPushAVP`.

**Acceptance Criteria:**
- Given a rebuilt package, when `CLICK=<prefix>/bin/click bats --tap tests` runs, then it exits 0 with every existing expectation unchanged, including the five `randomness-*` seeded tests.
- Given `DiameterEncap` and `DiameterAvpEncap` encoding the same packets as the pre-change build, when the output octets are compared, then they are identical.
- Given two `DiameterRatedSource` elements feeding one `DiameterPushAVP` on a Click built with `--enable-user-multithread`, when the config runs under `click -j 2`, then at least 50 frames are printed and every one is 36 octets with header Length `0x24`, AVP Length `0x10`, code `00000108` and eight hex value octets, with no drop warning.
- Given the same two-thread graph under a ThreadSanitizer build of Click and this package, when the run finishes, then ThreadSanitizer reports no data race in `DiameterEncap`, `DiameterAvpEncap` or `DiameterPushAVP`.
- Given a malformed message, when it reaches `DiameterPushAVP`, then the single drop warning and the zero output packets match today's behaviour.

## Spec Change Log

- 2026-11-17, operator-directed contract correction before re-dispatch. Finding: the blocked first run could not satisfy the two-thread row, which asked for a 40-octet frame (header Length `0x28`) while also fixing AVP Length `0x10`, an eight-octet value and a `DiameterRatedSource` input. Amended: the row and its acceptance criterion now read 36 octets and header Length `0x24`, and the row names the two-router-thread setup (`-j 2` with `StaticThreadSched`) that actually puts both sources on separate threads. Known-bad state avoided: a 40-octet frame needs a 24-octet message, which 20 header octets plus 4 leaves as a short AVP header, so no valid input produces it. KEEP: the eight-octet value, AVP Length `0x10`, the two `DiameterRatedSource` producers, the at-least-50-frames threshold, and the skip on a Click built without multithread support.
- 2026-11-17, review loop 1, triggered by the verification-gap finding that the new two-thread test passes unchanged on the pre-change package. Amended, all outside `<intent-contract>`: the `tests/configs/smp-push-avp.click` task now states that the config is a shape check and explains why (its AVP Length comes from configuration, so no interleaving can change it), and gives the two sources distinct Command Codes so the output attributes frames to a thread; two new tasks add `smp-encap.click` and `smp-avpencap.click`, whose elements derive Length and AVP Length per packet so unequal payload lengths make a cross-thread write visible; the `tests/smoke.bats` task now demands a status check before the skip, the generator alphabet instead of `[0-9a-f]`, both source markers, and a frame floor above one source's `LIMIT`; `tests/README.md` must state what each config proves and what it does not; Design Notes gained the measured discrimination argument and a ThreadSanitizer recipe; Verification gained the byte-identity procedure, the TSan build/run/filter commands, and the pre-change negative control. Known-bad state avoided: a suite that stays green when the refactor is reverted, and documentation claiming a detection the test does not have. KEEP: the local-copy refactor in all three elements, unchanged `click_random()` order and value precedence, `StaticThreadSched` plus `RATE 100000` as the way to get both sources onto two threads, the 36-octet/`0x24`/`0x10` shape, the skip on a Click without multithread support, and the header comments marking members as configuration only.

## Review Triage Log

### 2026-11-17 — Review pass
- verdicts: 35 findings — high 5, medium 13, low 16, false 1, maybe-false 0
- findings:
  - `[low]` `[reject]` B-01 AC omits the `StaticThreadSched` placement the run depends on — The fix is a contract edit; the run it describes does place both sources on two threads, so the criterion's outcome holds.
  - `[high]` `[bad_spec]` B-02 Config cannot exhibit the defect it pins; pre-change code passes it — Demonstrated by the verification-gap layer: 5/5 passes on `5af853c`. Spec task amended; configs added that can see it.
  - `[medium]` `[bad_spec]` B-03 Frame-count floor equals one source's `LIMIT`; two threads unproven — True: `STOP true` lets one source end the run at 50 frames. Task now requires per-source markers and a floor above one `LIMIT`.
  - `[low]` `[reject]` B-04 `Auto Run Result` empty and self-contradictory — That section is written at Finalize; the reviewed tree is a mid-run intermediate. A fix would be a spec edit.
  - `[medium]` `[bad_spec]` B-05 Two of the three changed elements have no concurrent coverage — True: the only two-thread config contains neither element. Two configs added.
  - `[low]` `[reject]` B-06 Byte-identity criterion has no procedure — Fix is spec prose; the procedure was run and is now in Verification, so the criterion is no longer unsupported.
  - `[low]` `[reject]` B-07 ThreadSanitizer step not reproducible as written — Fix is spec prose; a full recipe is now in Design Notes and Verification.
  - `[low]` `[defer]` B-08 `-t 2` survives in `stories.yaml` and `findings.md` — Pre-existing text outside this story; recorded as a deferred item.
  - `[low]` `[reject]` B-09 'No documentation change' contradicts the `tests/README.md` edit — Fix is a contract edit; the boundary reads on element documentation, which is untouched, and test documentation is part of a test change.
  - `[medium]` `[bad_spec]` B-10 Skip guard can mask a configure failure and is coupled to upstream wording — True: the warning is grepped before `$status` is checked. Task now orders the status check first.
  - `[medium]` `[defer]` B-11 CI never executes the new config, not even a parse check — Closing it needs a CI Click built with `--enable-user-multithread`, which the SPEC forbids this story from changing; recorded as deferred.
  - `[low]` `[reject]` B-12 Problem statement lists a `dh` member `DiameterPushAVP` does not have and misattributes stories 3-5 — True but cosmetic and inside the contract; the fix is a contract edit.
  - `[low]` `[reject]` B-13 Verification environment is host scratch state — Fix is spec prose; the note also carries the rebuild recipe, so it is reproducible.
  - `[low]` `[defer]` B-14 No follow-up recorded for the CI gap — Same subject as B-11; recorded as a deferred item.
  - `[high]` `[bad_spec]` E-01 Both sources emit identical 20-octet messages, so the append's length is fixed — Same defect as B-02, independently found; handled by the amended tasks.
  - `[medium]` `[bad_spec]` E-02 `[0-9a-f]{8}` matches any byte, so the value assertion is vacuous — True: `Print` renders every octet as hex. Task now pins the generator alphabet.
  - `[medium]` `[bad_spec]` E-03 Threshold 50 equals one source's `LIMIT` — Same defect as B-03; amended task raises the floor and adds markers.
  - `[low]` `[defer]` E-04 `push()`/`put()` can return 0 before the `memset` — Pre-existing: the pre-change code has the same null-deref shape at `diameteravpencap.cc:53-56`; not caused by this story.
  - `[high]` `[bad_spec]` E-05 Test does not pin the two-thread surface it claims to — Same defect as B-02, filed as a claim; handled by the amended tasks.
  - `[medium]` `[bad_spec]` E-06 `tests/README.md` claims a detection the test lacks — True; README task now requires an honest statement of what each config proves.
  - `[high]` `[bad_spec]` V-01 New test passes unchanged on the pre-change, racy implementation — Pre-verified by the gap layer with a rebuilt baseline; the root cause is the spec's test-design task.
  - `[medium]` `[defer]` V-02 Only two-thread test is skipped in CI — Needs `--enable-user-multithread` in CI, excluded by the SPEC non-goal; recorded as deferred.
  - `[medium]` `[bad_spec]` V-03 `DiameterEncap` and `DiameterAvpEncap` get no multi-thread exercise anywhere — True; two discriminating configs added.
  - `[medium]` `[bad_spec]` V-04 `tests/README.md` documents a detection the test does not have — Same as E-06; README task amended.
  - `[low]` `[bad_spec]` V-05 `thread preference 1 out of range` warning invisible on a plain Click — Real but cosmetic; the amended skip rule checks the exit status first, and the config is re-derived anyway.
  - `[high]` `[bad_spec]` IA-a Expectation locus is the element, the test's locus is graph stdout — Same subject as V-01: the test's discriminating power. Handled by the amended configs and the TSan recipe.
  - `[medium]` `[bad_spec]` IA-b Diff changes three elements, test exercises one — Same as B-05/V-03.
  - `[medium]` `[bad_spec]` IA-c Value octets wildcarded, so the value half of the defect is invisible — Same as E-02.
  - `[low]` `[reject]` IA-d Reviewed tree asserts the TSan evidence rather than carrying it — The evidence block is written at Finalize; a fix would be a spec edit.
  - `[medium]` `[bad_spec]` IA-e Skip guard is third-party text; nothing asserts two threads pushed — Same as B-03/B-10.
  - `[low]` `[reject]` IA-f Contract's member vocabulary does not match the code — Cosmetic and inside the contract; fix is a contract edit.
  - `[low]` `[reject]` IA-g 'Configuration only' lives in comments, not a compile-time constraint — Enforcing it (const members, accessors) adds surface for no demonstrated harm; the comment plus review is proportionate.
  - `[low]` `[reject]` IA-h TSan criterion names elements the reviewed graph does not contain — Fix is a contract edit; the criterion is still satisfiable and the added configs close the coverage gap in code.
  - `[low]` `[reject]` IA-i Narrow reading of the documentation clause chosen silently — Fix is a contract edit; the narrow reading is the coherent one, since element man pages are untouched.
  - `[false]` `[reject]` IA-j Informational: surfaces where the readings converge — Not a defect claim; it records agreement, and the arithmetic it cites is already consistent.

### 2026-11-17 — Review pass 2
- verdicts: 33 findings — high 0, medium 17, low 14, false 2, maybe-false 0
- findings:
  - `[low]` `[reject]` B2-01 Contract still pins the PushAVP shape check and gives the two discriminating configs no criterion — Fix is a contract edit; acceptance criterion 4 (ThreadSanitizer) is what objects to a revert, and it does — measured on the racy package.
  - `[medium]` `[patch]` B2-02 Acceptance says at least 50 frames, the test demands 51, and a correct build can produce exactly 50 — Patched: `smp-push-avp.click` raises `LIMIT` to 1000 and only source1 stops the router; the test floor is now 1000. Verified on one CPU: 1000 frames from source1 and 705 from source2.
  - `[medium]` `[patch]` B2-03 `deferred: []` contradicts five defer verdicts in the same file — Patched: seven deferred items written with summary/evidence/location/severity and validated as YAML.
  - `[medium]` `[defer]` B2-04 `-t 2` and the non-discriminating frame assertion survive in `stories.yaml` and `findings.md` — Queue artifacts outside this story's change set; recorded as a deferred item with the measured reason.
  - `[medium]` `[defer]` B2-05 `DiameterPopStorePushAVP` is a fourth writer the story does not acknowledge — Real and out of scope (finding A-8 names three elements); recorded as a deferred item naming `src/diameterpopstorepushavp.cc:69`.
  - `[medium]` `[patch]` B2-06 Nothing asserts the producers reached two threads; the guard depends on Click's exact warning — Patched: `smp_skip_or_fail` fails on a rejected `thread preference` and `tests/README.md` calls the `StaticThreadSched` line load-bearing. A config-only proof of the placement does not exist, so the rest is deferred.
  - `[medium]` `[patch]` B2-07 The deferral's reason is wrong (CI does execute the configs) and the README overstates a local pass — Patched: `tests/README.md` now says CI runs them and skips on the multithread warning, so a local pass over the same Click is the same check only for the non-concurrent tests. The `AGENTS.md` half is deferred: edits there are replaced on refresh.
  - `[medium]` `[patch]` B2-08 The README never says how to get a Click that runs the two-thread tests — Patched: build recipe with `--enable-user-multithread`, the package configure line and a `--filter 'smp-'` invocation.
  - `[low]` `[reject]` B2-09 `String valueString = datastring;` copies unconditionally per packet — The copy is one atomic increment and decrement on a configured String; avoiding it needs pointer indirection through the generator chain, which is more complexity than the measured cost earns.
  - `[medium]` `[patch]` B2-10 `STOP true` on both producers makes the frame floors timing-dependent — Patched with B2-02: only the shorter-lived source stops the router, so the other keeps pushing; one CPU run produced 9952 and 9664 frames.
  - `[low]` `[patch]` B2-11 The 'once per few hundred frames' sizing claim is unsourced — Patched: the configs and README now cite the measurement (20 to 37 mismatched frames in roughly 9500 on the racy build) instead of an unsourced rate.
  - `[low]` `[reject]` B2-12 Two contract sentences are false about the code — Fix is a contract edit; the member list and the documentation boundary are inside the intent-contract, and the code matches the approach sentence where it matters.
  - `[low]` `[reject]` B2-13 `Auto Run Result` promises a result it does not contain — That section is written at Finalize; this pass fills it.
  - `[low]` `[defer]` E2-01 `push()`/`put()` can return 0 before the `memset` in both encoders — Pre-existing at `5af853c`; deferred with the location and severity.
  - `[medium]` `[patch]` E2-02 The second PushAVP source can push nothing before source1 hits its limit — Patched with B2-02; measured on one CPU before and after.
  - `[medium]` `[patch]` E2-03 One encoder source can reach its limit before the other pushes once — Patched with B2-10; both shapes are still required, so an empty shape still fails.
  - `[medium]` `[patch]` E2-04 A reworded or absent multithread warning turns a skip into a failure — Patched: the gate checks the status first and fails on a rejected thread preference, which is independent of the multithread warning's text.
  - `[false]` `[reject]` E2-05 Claim: the pre-change package passes all three tests 3/3 — Refuted twice: the intent layer ran the pre-change package and got failures with `28 | 01000018 …` and `16 | 00000108 0000000c …`, and this pass reran the bats suite against `5af853c` with `not ok 2` and `not ok 3`. The claim's setup must have loaded the fixed module.
  - `[medium]` `[defer]` V2-01 Reverting the PushAVP change leaves every smoke test green — Pre-verified and true: only ThreadSanitizer separates the two builds for that element. Automating TSan is CI work the SPEC excludes, so it is deferred with the evidence and with the manual recipe in Design Notes.
  - `[medium]` `[defer]` V2-02 The only two-thread tests are skipped by the CI job — Pre-verified; needs `--enable-user-multithread` in CI, excluded by the SPEC non-goal. Deferred with the corrected statement that CI does run them single-threaded.
  - `[medium]` `[patch]` V2-03 The tests pass on the racy package when the `StaticThreadSched` line is absent or ignored — True and measured by the layer. Patched as far as a config allows: a rejected preference now fails the test and the README marks the line load-bearing; the absence of a thread-placement readout is deferred.
  - `[medium]` `[patch]` V2-04 `smp-push-avp` fails a correct build on a single-core machine — Patched: `LIMIT` 1000 and a single stopping source. Re-verified under `taskset -c 0`: 1000 + 705 frames, test passes.
  - `[medium]` `[reject]` V2-05 The TSan criterion can be satisfied by an uninstrumented package, which the Environment note invites — Fix is spec prose; the note is corrected in this pass's Finalize write-up, and the negative control in Verification is what exposes the trap.
  - `[low]` `[reject]` IA2-a The matrix row's expectation is not a property of the defect — Fix is a contract edit; the story documents the limitation and the TSan criterion covers the element.
  - `[low]` `[reject]` IA2-b The discriminating tests exercise a producer the contract does not name — Fix is a contract edit; the substitution is documented in the task and the properties under test are unchanged.
  - `[low]` `[reject]` IA2-c Byte identity is asserted at a golden-comparison surface no in-repo artifact provides — Fix is spec prose; the procedure is now a Verification command and was run for all 72 configs.
  - `[low]` `[reject]` IA2-d The contract's member inventory disagrees with the code — Contract edit.
  - `[low]` `[patch]` IA2-e The PushAVP header local is declared mid-function, not with the other locals — Patched: `AvpHeader header = ah;` moved up with the value locals.
  - `[low]` `[reject]` IA2-f 'Configuration only' is prose, not a compile-time constraint — Enforcing it would add const members or accessors for a harm no caller can reach; proportionate as is.
  - `[low]` `[reject]` IA2-g The narrow documentation reading is chosen silently — Contract edit; element man pages are untouched, which is the reading the boundary supports.
  - `[medium]` `[defer]` IA2-h Two-thread evidence is not executed by the recipe the repo treats as the check — Same subject as V2-01/V2-02; recorded deferred.
  - `[false]` `[reject]` IA2-i Reconfiguration would now see the configured value instead of the last generated one — No reconfigure path exists for this element: it has no live-reconfigure handler, and Click replaces elements on hot reconfiguration, so the delta cannot be observed.
  - `[low]` `[reject]` IA2-j The refactor shifts per-packet cost — Same subject as B2-09; output is unchanged and the cost is an atomic pair on a configured string.

## Design Notes

Copying the configured header per packet is cheap and correct: `DiameterHeader` and `AvpHeader` are plain structs with initialising constructors, and `String`'s reference count is atomic (`include/click/string.hh:256-259`), so reading the configured `String` from two threads is safe while no one writes it. That is exactly the invariant this story creates: `configure()` writes members, `simple_action()` only reads them.

The value precedence in `DiameterPushAVP` is subtler than its man page: with `RANDUINT32 true` and a non-empty `OCTETSTRING`, the code still draws a random number and then emits the configured string, because the length test prefers `datastring`. Preserve the draw as well as the output; dropping it would shift every later draw and break the seeded tests.

Golden before/after for the seeded append (`randomness-push-avp.click` shape): the frame is unchanged octet for octet; only the storage of the intermediate value moves from the element to the stack.

Two facts about the harness, checked against Click `9197a594b`:

- The thread option is `-j N` (`--threads`); `-t` is `--time`, so a `click -t 2` run prints timings and stays single threaded. The findings' repro line says `-t 2`; use `-j 2`.
- Multithreading is a build option. Without `./configure --enable-user-multithread` the binary prints `warning: Click was built without multithread support, running single threaded` and `-j 2` silently degrades, so the tests skip on that warning. CI builds Click with the flag since story 10, so the gate runs them; a local plain build still skips, and the ThreadSanitizer run stays local.
- Two upstream elements may feed one push input port: `c :: Counter -> Discard; InfiniteSource(...) -> c; InfiniteSource(...) -> c;` parses and runs on the built binary, so no joining element is needed for the repro.
- The repro needs `StaticThreadSched(source1 0, source2 1)`: Click's `ThreadSched::initial_home_thread_id()` returns 0, so `-j 2` alone leaves both source tasks on thread 0 and no race can occur. `RATE 100000` keeps the token bucket full so the 50 packets leave back to back instead of at the default ten per second.

### Frame arithmetic

A `DiameterRatedSource` emits a 20-octet header-only message, and one append adds an 8-octet AVP header plus an 8-octet value, so the frame is **36 octets with message Length `0x24`** and AVP Length `0x10`. A 40-octet frame would need a 24-octet incoming message, and 24 = 20 + 4 leaves four octets after the header, which `diameter_check_message()` rejects as a short AVP header -- so no valid input produces one, and the 36/`0x24` figures are the only ones consistent with an eight-octet value.

### What the two-thread tests can and cannot see

`DiameterPushAVP` takes its AVP Length from configuration, so every packet it appends has the same Length no matter which thread wins the race: a frame-level assertion over its output cannot distinguish the fixed element from the racy one. Measured: the pre-change package passes the `smp-push-avp` shape check five times out of five. Its test is therefore a shape and regression check, and ThreadSanitizer is what proves the element. The shared `String` write is the most damaging part of that element's race and corrupts value octets that any regex over hex output accepts.

`DiameterEncap` and `DiameterAvpEncap` are different: their Length, AVP Length and padding all derive from the packet in hand, so with two producers sending different payload lengths a cross-thread write leaves the declared Length disagreeing with the frame. Their two configs are the frame-level negative control, and they must fail on the pre-change package.

The reproducible negative control for all three elements is ThreadSanitizer: on `5af853c` the same graph reports races rooted at `diameterpushavp.cc:139` (`datastring = randString(...)`) and aborts; on the fixed package no report names any of the three files.

### ThreadSanitizer recipe

TSan is not wired into CI, so this is a local check even though CI now builds Click with multithread support (story 10).

```bash
git -C ~/git/click archive 9197a594b | tar -x -C "$HOME/src/click-tsan"
cd "$HOME/src/click-tsan" && env CXXFLAGS="-fsanitize=thread -g -O1" LDFLAGS="-fsanitize=thread" \
  ./configure --prefix="$HOME/click-tsan" --disable-linuxmodule --enable-user-multithread
env CXXFLAGS="-fsanitize=thread -g -O1" LDFLAGS="-fsanitize=thread" make -j8 && make install

cd <package-lf-export> && autoconf && ./configure --with-click="$HOME/click-tsan" --prefix="$HOME/click-tsan"
make -j8 CXXFLAGS="-fsanitize=thread -g -O1 -Wall -Wextra -fPIC -shared" \
     && make install CXXFLAGS="-fsanitize=thread -g -O1 -Wall -Wextra -fPIC -shared"
```

Overriding `CXXFLAGS` for the package must keep `-fPIC -shared`, or the link fails with a relocation error. Click's own shutdown races make TSan exit 66; judge a run by its reports, not its exit status:

```bash
$HOME/click-tsan/bin/click -j 2 tests/configs/smp-push-avp.click 2>&1 \
  | grep -E 'diameter(encap|avpencap|pushavp)\.cc'
```

The expected output is empty on the fixed package and non-empty on `5af853c`.

## Verification

**Commands:**
- `autoconf && ./configure --with-click=PREFIX --prefix=PREFIX && make && make install` -- expected: builds with no warnings under `-Wall -Wextra`
- `CLICK=PREFIX/bin/click bats --tap tests` -- expected: every test passes; the `smp-*` tests skip only on a Click without multithread support
- `PREFIX/bin/click -j 2 tests/configs/smp-push-avp.click` on a Click built with `--enable-user-multithread` -- expected: at least 50 frame lines, each 36 octets (20-octet message plus a 16-octet AVP), both source Command Codes present, no drop warning, no multithread warning
- `PREFIX/bin/click -j 2 tests/configs/smp-encap.click` and `... smp-avpencap.click` -- expected: every printed frame's declared Length matches its printed octet count and both payload lengths appear
- Byte identity: install the package at `5af853c` into a second prefix, prepend `RandomSeed(SEED 12345)` to each config without a seed, and compare stdout, stderr and exit status for every config except the `smp-*` ones -- expected: identical
- Negative control: run the three `smp-*` configs against the `5af853c` package under the ThreadSanitizer build -- expected: reports naming `diameterpushavp.cc` (and the other two files for their configs); on the fixed package the filter below prints nothing
- `click-tsan -j 2 CONFIG 2>&1 | grep -E 'diameter(encap|avpencap|pushavp)\.cc'` -- expected: empty output; TSan's exit status is 66 from Click-core races and is not the verdict

**Environment:** `/tmp/opencode` holds Click `9197a594b` built three ways -- `click-master` (plain), `click-mt` (`--enable-user-multithread`) and `click-tsan` (`--enable-user-multithread` with `-fsanitize=thread -g`) -- plus `bats-core/bin/bats` 1.14. Install this package into `click-master` and `click-mt` with a plain `make install`, but into `click-tsan` **only** with the sanitizer `CXXFLAGS` from the recipe above: an uninstrumented module loaded by the TSan binary reports nothing at all, so a plain install there would make the ThreadSanitizer check pass for the racy package too. Check with `ldd "$HOME/click-tsan/lib/diameter.uo" | grep tsan` before trusting a run. If a prefix is missing, rebuild it from `git -C ~/git/click archive 9197a594b`.

## Auto Run Result

Status: done

**Change.** The three writers copy the configured header and value into locals inside `simple_action()` and never write an element member after `configure()`, so two router threads can no longer stamp a frame with another packet's Length or corrupt a shared `String` (finding A-8, CAP-5). Bytes, arguments, drop reasons and the order of `click_random()` draws are unchanged.

**Files changed.**
- `src/diameterencap.cc` -- local `DiameterHeader` per packet; hop-by-hop, end-to-end and Length set on the local.
- `src/diameterencap.hh` -- `dh` marked configuration only.
- `src/diameteravpencap.cc` -- local `AvpHeader`; header length, AVP Length and padding all derived from it.
- `src/diameteravpencap.hh` -- `ah` marked configuration only.
- `src/diameterpushavp.cc` -- local `AvpHeader`, `String` and value word; the value precedence and draw order are untouched.
- `src/diameterpushavp.hh` -- members marked configuration only.
- `tests/configs/smp-push-avp.click` -- two threads into one `DiameterPushAVP`; shape check with a Command Code per source.
- `tests/configs/smp-encap.click` -- two threads, two payload lengths into one `DiameterEncap`; a cross-thread write contradicts the printed frame length.
- `tests/configs/smp-avpencap.click` -- the same for `DiameterAvpEncap` and its AVP Length.
- `tests/smoke.bats` -- `run_click_threads`, `smp_skip_or_fail` and the three `smp-*` tests.
- `tests/README.md` -- what each `smp-*` config proves and the multithread build recipe.

**Review.** Two passes. Pass 1: 35 findings, five high; the high ones were one defect -- a two-thread config whose frame assertion the racy package passed -- routed `bad_spec`, so the code was reverted and re-derived from an amended spec that added the two discriminating configs and a ThreadSanitizer recipe. Pass 2: 33 findings, no high, 17 medium, 14 low, two false. Six grouped patches applied: higher `LIMIT` with a single stopping source and matching floors; a `deferred` list; a thread-placement gate that fails on a rejected preference; README corrections (multithread recipe, CI truth, measured mismatch rate); the unsourced rate replaced by the measurement; the PushAVP header local moved up with the other locals. Seven items deferred (two of them closed afterwards by story 10, which put `--enable-user-multithread` into CI): CI cannot run the two-thread tests; the PushAVP `String` race is TSan-only; `DiameterPopStorePushAVP` is a fourth writer; the `-t 2` text in `findings.md`/`stories.yaml`; no config-only thread-placement readout; unchecked `push()`/`put()` in the encoders; the `AGENTS.md` sentence about a local pass. Rejected findings were contract edits (the contract is the operator's), prose already settled by this pass's write-up, or not defects (no reconfigure path exists for the element). One claim -- that the pre-change package passes all three tests -- was refuted by two independent runs and rejected as false.

**Verification.** `-Wall -Wextra`: zero warnings. Suite on `--enable-user-multithread` Click: 94/94, no skips. Suite on a plain Click: 94, three `smp-*` skips with the reason. Byte identity against `5af853c`: all 72 non-`smp` configs, `RandomSeed(SEED 12345)` prepended where absent, identical stdout, stderr and exit status. Negative control: the same three tests against the `5af853c` package fail on `smp-encap` and `smp-avpencap` with frames such as `28 | 01000018 ... deadbeef 01020304`, and pass on `smp-push-avp` as documented. ThreadSanitizer on the fixed package: zero report lines naming any of the three element files across the three configs; on `5af853c`, 44, 6 and 4 lines naming `diameterpushavp.cc`, `diameterencap.cc` and `diameteravpencap.cc` respectively. One-CPU repeat (`taskset -c 0`): 1000 and 705 frames, both Command Codes present, suite green.

**Residual risks.** The shared-`String` race in `DiameterPushAVP` cannot be seen by a frame assertion, because its AVP Length comes from configuration; ThreadSanitizer was the detector, and at the time of this pass it was a local procedure. Story 11 wired it into CI, so that risk is now gated. The gate also exercises two real threads, since story 10 builds CI's Click with `--enable-user-multithread`.

**Risks noted, not defects.** Frame floors depend on the two producers overlapping; the `LIMIT` raise and single stopping source make that robust on one CPU but not provable from a config. A missing `StaticThreadSched` line would quietly restore a passing shape check, which is why the tests fail on a rejected thread preference and the README marks the line load-bearing.

**Follow-up, 2026-11-17.** Story 10 closed this story's two CI-related deferred items: the workflow now builds Click with `--enable-user-multithread`, so the three `smp-*` tests run in the gate instead of skipping, and `tests/README.md` no longer says otherwise. Story 11 closed the third: a `thread-sanitizer` job now runs `tests/tsan-check.sh` over the same configs and fails on any race whose racing access is inside this package, so the shared-`String` class is gated rather than hand-checked. With that, the recommendation to review again is satisfied and `followup_review_recommended` is cleared.
