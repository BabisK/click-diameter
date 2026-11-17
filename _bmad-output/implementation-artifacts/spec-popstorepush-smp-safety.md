---
title: 'Make DiameterPopStorePushAVP safe under more than one thread'
type: 'bugfix'
created: '2026-11-17'
status: 'done'
route: 'dispatch'
review_loop_iteration: 0
baseline_commit: '7ac78a948dba0deb672473bfbe154a34a0228991'
context: ['{project-root}/AGENTS.md']
---

<frozen-after-approval>

## Intent

**Problem:** `DiameterPopStorePushAVP` is the fourth writer that keeps per-packet state in element members, and the one story 1 of `spec-diameter-rfc-conformance` left out of finding A-8. `push()` picks the output port from the member `data`, and `process()` decodes, mutates and encodes the member `AvpHeader ah` and refills `data` inside the packet path. Click does not serialise a push element across router threads, so two packets can interleave between decode and encode, and one frame is stamped with the other's header or the store is freed twice. Measured at `7ac78a9`: the two-thread config segfaults after 69 frames and ThreadSanitizer reports 36 races with access frames in `src/diameterpopstorepushavp.cc`. The single-threaded run is correct, which is why every existing test passes.

**Approach:** keep the one store the element documents, and make it safe: build the AVP header per packet, publish it into the store only while holding a Click `Spinlock`, and hold that lock across the store decision and the packet rewrite so the sequence-global rule survives a packet that returns on another thread. Release it before pushing downstream. Output bytes, arguments, drop reasons and the retained-store-on-overflow rule stay as they are.

**Decision:** the store stays a single shared one guarded by a `Spinlock`, not one store per router thread. Click assigns a packet's push to the thread of the task that released it, and a `Queue` in the element's documented self-loop — or a scheduler calling `Task::change_thread` — can return a message on a different thread; a per-thread store would then silently never complete the pair.

## Boundaries & Constraints

**Always:** single-threaded output stays byte-identical, so every existing `popstorepush-*` expectation keeps its bytes; the documented pairing rule is unchanged — the packet that arrives while an AVP is stored appends it, whichever thread delivers it; the lock is released before `output(port).push()` so no downstream element runs under it; the existing warnings, the no-AVP no-op and the rule that an overflow drop keeps the stored AVP are unchanged; `ah` and `data` are touched only under the lock; tabs for indentation; warning-free at `-Wall -Wextra`.

**Never:** no per-thread sharding, no `click_current_cpu_id()` indexing, and no refusal to run on a multithread router; no new or changed argument and no port-count change; no wire-format change; no edit to `DiameterEncap`, `DiameterAvpEncap`, `DiameterPushAVP` or `DiameterPopAVP`; no edit to `.github/workflows/`, whose sanitizer job already globs `tests/configs/smp-*.click`; no persistent state.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Unarmed first packet | 44-octet message, two 12-octet AVPs | 32 octets on output 0, Length `0x20`, first AVP | None |
| Armed second packet | the same message again, one AVP stored | 56 octets on output 1, Length `0x38`, its two AVPs plus the stored copy | None |
| Two threads, one element | two producers with distinct AVP markers on threads 0 and 1 | every frame is well formed (32 or 56 octets, each AVP 12 octets with its Length intact), both producers appear on both outputs, no crash; an output-1 frame may carry the other producer's marker because the store is shared | None |
| No-AVP first packet | 20-octet message, store unarmed | forwarded unchanged to output 0, nothing stored | None |
| Malformed, store armed | bad AVP in the packet | one drop line, nothing on either output, store unchanged | `dropping malformed packet: REASON` |
| Stored AVP past the ceiling | armed store, message near `0xFFFFFF` | packet dropped naming the three-octet field, store kept | `dropping packet: ... three-octet Length field` |
| Click without multithread support | the new `smp-*` config | the test skips with the existing reason | Skip |

</frozen-after-approval>

## Code Map

- `src/diameterpopstorepushavp.cc:25-41` -- `push()` reads the member `data` to pick the port before `process()`; the port decision must be captured under the lock.
- `src/diameterpopstorepushavp.cc:43-106` -- `process()`: decode into `ah` (`:69`), value allocation and copy (`:71-72`), the ceiling guard that keeps the store (`:87-92`), the append that re-encodes `ah` and frees `data` (`:93-103`).
- `src/diameterpopstorepushavp.hh:66-70` -- the two members; `:24-49` the `=d` page, which already says `carries no AVPs` and `stored AVP would exceed`.
- `src/diameter.hh:234-349` -- `AvpHeader`, trivially copyable with every field initialised; `diameter_check_message` at `:466` is pure over the buffer.
- `include/click/sync.hh:22-65` -- `Spinlock`; a no-op unless Click is built with multithreading, recursive, and cheap when uncontended.
- `~/git/click/elements/ip/ipratemon.cc:81-121` -- the in-tree precedent: a `Spinlock` allocated for element state and acquired in `push()` around the shared update; `elements/ip/ipratemon.hh:165` declares it.
- `~/git/click/lib/router.cc:374-378`, `lib/router.cc:1944` -- every task defaults to thread 0 and `ThreadSched::initial_home_thread_id()` is 0 unless bound; `doc/click.texi:1262-1284` -- `Task::change_thread` can move a task at run time.
- `tests/configs/popstorepush-roundtrip.click` -- the 44-octet two-AVP message model and the self-loop the new config reuses.
- `tests/smoke.bats:114-146` -- `run_click_threads`/`smp_skip_or_fail`, the gate every `-j 2` test uses; `:1131-1190` the single-threaded `popstorepush-*` tests.
- `tests/tsan-check.sh`, `tests/manpages.bats:145-150,224-260`, `tests/README.md:106-150,324-326,384-387` -- sanitizer entry point, the installed-page assertions, and the `smp-*` paragraph (which says "three") plus the two config tables.

## Tasks & Acceptance

**Execution:**
- [x] `src/diameterpopstorepushavp.hh` -- declare a `Spinlock` beside the store and comment that `ah` and `data` are touched only under it; extend `=d` with the thread rule, keeping both existing phrases -- the page is how a caller learns that the pairing rule is sequence-global.
- [x] `src/diameterpopstorepushavp.cc` -- include `<click/sync.hh>`; in `push()` acquire the lock, capture the port from `data`, call `process()`, release, then push downstream; in `process()` decode into a local `AvpHeader` and publish it into the store when arming -- removes the unguarded member writes and keeps every downstream call outside the lock.
- [x] `tests/configs/smp-popstorepush.click` -- two `InfiniteSource` producers on threads 0 and 1 (`StaticThreadSched`), each sending the same 44-octet message with a distinct four-octet marker in both AVPs; one `Print` per output (`MAXLENGTH 200, CONTENTS HEX`), `LIMIT 5000`, `STOP true` on one producer only.
- [x] `tests/smoke.bats` -- one test (`run_click_threads 2`, `smp_skip_or_fail`) requiring exit 0, only well-formed 32- and 56-octet frames whose AVP Lengths match their values, both producers on both outputs, and a frame floor; a crashed run or a truncated AVP fails it.
- [x] `tests/manpages.bats` -- assert the page states that one shared store survives a packet returning on another thread, in the style of the existing prose assertions.
- [x] `tests/README.md` -- add the config row, say what it proves (shape and no crash) and what it does not (marker mixing is legal; ThreadSanitizer is the proof), and correct the `smp-*` count from three to four.
- [x] `_bmad-output/implementation-artifacts/deferred-work.md` -- remove both entries: the first closes here, the second is dropped by operator decision as `BabisK/click` work; evidence goes in the owning stories' triage logs.

**Acceptance Criteria:**
- Given the built package, when `CLICK=<prefix>/bin/click bats --tap tests` runs, then it exits 0 with every existing expectation unchanged.
- Given the seven `popstorepush-*` configs at the new package, when their output is compared with `7ac78a9`, then stdout, stderr and exit status are identical under one seed.
- Given two producers on two threads feeding one element, when the run finishes, then it exits 0 with at least 5000 frames, every frame is 32 or 56 octets with AVP Lengths that match their values, both markers appear on both outputs, and no drop warning is printed.
- Given the pre-change package at `7ac78a9` and the same config on two threads, then the run crashes -- the negative control proves the test discriminates.
- Given a ThreadSanitizer Click and package, when `tests/tsan-check.sh` runs over `tests/configs/smp-*.click`, then no report names `diameterpopstorepushavp.cc`.
- Given a Click built without multithread support, when the new test runs, then it skips with the existing reason instead of passing.

## Implementation Notes

- `push()` takes the lock once, reads `data` for the port, calls `process()` and
  releases before `output(port).push()`. `process()` decodes into a local
  `AvpHeader` and publishes `this->ah` and `data` together only while arming, so
  the store has one writer-side sequence and the members are touched only under
  the lock.
- **ThreadSanitizer cannot see Click's Spinlock.** A Click `Spinlock` is an
  inline-assembly `xchg` loop, and ThreadSanitizer instruments neither the
  `xchg` nor the plain `_lock`/`_owner`/`_depth` accesses around it (reproduced
  with a two-thread probe: 4 races on a counter guarded by a bare `Spinlock`).
  With a bare lock the sanitizer therefore reported the protected `data`/`ah`
  accesses at `diameterpopstorepushavp.cc:35,79,80,111` as races and the lock
  internals in `click/sync.hh` and `click/atomic.hh`, although the `xchg` gives
  the ordering on every architecture Click supports. The element announces the
  critical section with `__tsan_acquire`/`__tsan_release`, compiled only when
  `__SANITIZE_THREAD__` is defined (a no-op otherwise), and
  `tests/tsan-check.sh` no longer counts a `#0` frame in Click's own lock
  implementation. The gate still names any report whose access is on the
  element's own line: the `7ac78a9` package fails it at `:27`, `:103` and the
  `AvpHeader` frames in `diameter.hh`.
- `tests/configs/smp-popstorepush.click` reuses the 44-octet two-AVP message of
  `popstorepush-roundtrip.click`. Each producer's hop-by-hop/end-to-end pair
  (`00000001 00000002` and `00000003 00000004`) identifies it after a frame
  leaves the element, because the shared store legitimately mixes the AVP
  markers on output 1.
- **Correction (2026-11-17).** The acceptance text's "seven `popstorepush-*`
  configs" is wrong: nine `*popstorepush*.click` configs exist and were compared
  — four `popstorepush-*` (`popstorepush-roundtrip`, `popstorepush-mandatory`,
  `popstorepush-length-overflow`, `popstorepush-store-retained`) and five
  `malformed-*` (`malformed-avp-in-message-popstorepush-vendor-id-zero`,
  `malformed-popstorepush-armed`, `malformed-popstorepush-avp-length`,
  `malformed-retransmit-on-answer-popstorepush`,
  `malformed-version-popstorepush`). All nine produced identical stdout, stderr
  and exit status under one seed.
- **Review fixes (2026-11-17).** Validation moved out of the lock: `push()`
  calls `diameter_check_message()` and drops a malformed packet before
  `lock.acquire()`, and `process(Packet*, uint32_t lastAvpOffset)` now holds the
  lock only for the store decision and the rewrite. The sanitizer shim is
  compiled from `<sanitizer/tsan_interface.h>` when `__SANITIZE_THREAD__` is
  defined or `__has_feature(thread_sanitizer)` is true, so the earlier note's
  "compiled only when `__SANITIZE_THREAD__` is defined" is superseded, and no
  `extern "C"` declaration sits inside `CLICK_DECLS`. `tests/tsan-check.sh`
  supersedes its earlier blanket header exclusion: a report is ignored only when
  its racing `#0` access is in `include/click/sync.hh`/`atomic.hh` **and** the
  same report's stack names `Spinlock::`, so a package race that inlines into
  `atomic.hh` is still reported. `tests/configs/smp-popstorepush-loop.click`
  adds the missing pairing proof: a pop on thread 0 whose remainder returns
  through a `Queue`/`DelayUnqueue` task bound to thread 1 must still find the
  stored AVP, and a thread-local mutant prints a second 20-octet output-0 frame
  instead of the 44-octet output-1 frame the test pins.
- **Verification at the reviewed tree.** `-Wall -Wextra` build: zero warnings.
  `bats --tap tests` with `CLICK_TIMEOUT=30`: 170/170, no skips.
  `tests/tsan-check.sh` over the five `smp-*.click` configs: `ok` for each. The
  `7ac78a9` package still crashes on `smp-popstorepush` (3/3 runs, exit 139) and
  fails the sanitizer check; the byte-identity comparison against it is
  unchanged for the nine `*popstorepush*` configs under one seed. The sanitizer
  filter was exercised on a synthetic report file: a lock-only report is
  ignored, a package report prints its `#0` frames even when the stack mentions
  `Spinlock::`, and a bare `atomic.hh` report is still printed.
- **Environmental finding, not caused by this change.** With the suite's default
  `CLICK_TIMEOUT=10`, `identifiers-rated-source-pull-unique` times out on this
  host: the `--simtime` run at `RATE 10` takes about 12.2 s on the multithread
  Click at 3.19 GHz, and about 12.4 s with the `7ac78a9` module, while the plain
  Click build takes 6.0 s. The same test passed at 21:52 and consistently times
  out at 22:13 with no code change, so the margin tracks CPU clock. Recorded in
  `deferred-work.md` rather than fixed here.

## Spec Change Log

## Review Triage Log

| # | Layer | Finding | Verdict | Evidence / disposition |
|---|-------|---------|---------|------------------------|
| 1 | deferred | `DiameterPopStorePushAVP` is a fourth push writer that still keeps per-packet state in members, with no `smp-*` config and no sanitizer run | done | Closed here: the store is a `Spinlock`-guarded shared one held across the decision and the rewrite, `smp-popstorepush.click` runs two producers on two threads, and `tests/tsan-check.sh` covers it. The pre-change package exits 139 on the config and fails the sanitizer check; this build passes both. |
| 2 | deferred | The upstream `BabisK/click` fork still carries `conf/test.click` and a stale in-tree copy of these elements | not-doing | Closed by operator decision: the removal is one commit in that fork, so nothing in this package can perform or verify it (F-16 of `spec-diameter-package-hardening`). |

### 2026-11-17 — Review pass

`blind` = blind hunter, `edge` = edge-case hunter, `vgap` = verification-gap reviewer. Every row was verified at the cited location; duplicates keep the first row and name the other layer.

| # | Layers | Finding | Verdict | Route | Evidence |
|---|--------|---------|---------|-------|----------|
| R-1 | blind, edge, vgap | `README.md` still calls the element's race open and points at the emptied `deferred-work.md` | medium | patch | Verified at `README.md:339-347`; the section now names only F-16 and no ledger. |
| R-2 | blind, vgap | `.github/actions/build-click/action.yml` still says "three `smp-*` configs" | low | patch | Verified at `action.yml:57`; now five. |
| R-3 | vgap, blind | Nothing proves the shared-store rule: a per-thread store passes the new test | medium | patch | vgap measured a `thread_local` mutant passing `smp-popstorepush`; reproduced here — the mutant prints out0 32, out0 20, out1 32 on `smp-popstorepush-loop`, the fixed build prints out0 32 then out1 44. Config and test added. |
| R-4 | blind, edge | Requiring each producer's markers on each output fails a correct element on a legal schedule | low | patch | The store alternates pop/append globally, so perfect alternation can put one producer only on the armed slot; the test now requires both producers' pairs somewhere, both outputs non-empty, and the shapes. |
| R-5 | blind | The marker loop duplicates the producer loop | low | patch | Deleted with R-4. |
| R-6 | blind | The frame floor is too tight and too weak | false | — | Exactly 5000 frames means source `b` never pushed, which is the run the test must fail; the floor is a participation guard, not a proof of two threads. |
| R-7 | blind, edge | Message validation and `click_chatter` run under the spinlock | medium | patch | Validation is pure over the buffer; `push()` now checks before `lock.acquire()` and `process()` receives `lastAvpOffset`. The store decision and rewrite stay under the lock. |
| R-8 | blind, vgap | `tests/tsan-check.sh` drops every `#0` frame in `sync.hh` and `atomic.hh` for all reports | medium | patch | The exclusion is now report-scoped: lock header plus `Spinlock::` in the same stack. Exercised on a synthetic file — lock-only ignored, package and bare-atomic reports printed. |
| R-9 | blind, edge | The sanitizer shim is gated on `__SANITIZE_THREAD__` alone | low | patch | Added `__has_feature(thread_sanitizer)` and `<sanitizer/tsan_interface.h>`, so a Clang build keeps the annotations. |
| R-10 | blind | `extern "C"` declarations inside `CLICK_DECLS` are unsound under `--enable-namespace` | false | — | C++ `[dcl.link]` equates C-linkage declarations in different namespace scopes; the symbol resolved in the sanitizer run. The header include removes the declarations regardless. |
| R-11 | blind | The destructor frees `data` and the constructor initialises it outside the lock, contradicting the invariant | low | patch | Comments now say the invariant is the packet path and that the constructor/destructor run with no packet in flight. |
| R-12 | blind | The publication comment claims an atomic publish that five scalar stores do not provide | low | patch | Comment now says `data` is assigned last under the lock, so the store is never armed with a header but no value. |
| R-13 | blind | The spec's measurements disagree across sections (69 vs 101–542 frames; baseline vs tree line numbers) | reject | — | Spec text: the frozen AC/Verification and the Design Notes are operator-owned. The two sets are baseline lines for baseline runs and this-tree lines for this tree, as the Implementation Notes now state. |
| R-14 | blind, edge | The spec says "seven `popstorepush-*` configs" where nine `*popstorepush*` configs exist | reject | — | Spec text; the Implementation Notes correction names four `popstorepush-*` and five `malformed-*` and records the comparison. |
| R-15 | blind | The TSan probe that justifies the annotation is not committed | reject | — | Low, and no user-visible harm: the rationale is on the element, the script and `tests/README.md`, and R-3's mutant demonstrates the pairing the lock exists for. A probe element would be dead code. |
| R-16 | blind, edge | The planned closure evidence never reached the owning stories' triage logs | medium | patch | The spec's own task requires it. Rows appended to `spec-diameter-rfc-conformance/stories/1-…` and `spec-diameter-package-hardening/stories/8-…`, citing this spec. |
| R-17 | blind | `stories.yaml` and `sprint-status.yaml` were not updated | reject | — | Planning bookkeeping outside the intent; the closure is recorded in the two owning triage logs and this spec, which is the record the spec's task names. |
| R-18 | blind | The triage log carried pre-review verdicts, no layer preamble and no PR evidence | reject | — | Spec text; the rows above are this pass, and no pull request exists until the branch is pushed. |

## Design Notes

- **Measured.** At `7ac78a9` a two-producer config of the new shape (markers `41414141`/`42424242`, threads 0 and 1) exits 139 after 69 frames on `click-mt`; on `click-tsan` the same run reports 36 `data race` entries at `diameterpopstorepushavp.cc:27` (the `data == NULL` test), `:69`, `:71`, `:87` and `:97`.
- **Why not per thread.** A push runs on the thread of the task that released the packet (`output(port).push()` is a direct call), so a packet keeps its thread only while it stays in one push chain. A `Queue` is a push-to-pull boundary: its own task later pushes downstream on the queue's thread, which defaults to 0. The element's documented loop (`psp[0] -> Print -> psp`) with a queue in it, or a scheduler moving the producer task, would therefore pair a pop on one thread with a push on another, and a per-thread store would leave the AVP stored and emit the later packet on output 0 with no diagnostic.
- **Lock scope.** `push()` holds the lock across the store decision and the rewrite, and releases before `output(port).push()`: a downstream element must never run under this element's lock, and the store decision cannot be separated from the rewrite without a reservation state that is a lock in disguise.
- **Every input is one output frame.** Each producer alternates 32- and 56-octet frames, and the two producers' counts are not comparable. With a shared store an output-1 frame legitimately mixes markers, so marker equality is not a sound assertion; malformed AVP Lengths and a crash are.

## Verification

**Commands:**
- `autoconf && ./configure --with-click=/tmp/opencode/click-mt --prefix=/tmp/opencode/click-mt && make CXXFLAGS="-g -O2 -Wall -Wextra -fPIC -shared" && make install` -- expected: exit 0, zero warnings.
- `CLICK=/tmp/opencode/click-mt/bin/click /tmp/opencode/bats-core/bin/bats --tap tests` -- expected: exit 0, no skips on this Click.
- `/tmp/opencode/click-mt/bin/click -j 2 tests/configs/smp-popstorepush.click` -- expected: at least 5000 well-formed frames, both markers on both outputs, no drop warning, no crash.
- `tests/tsan-check.sh /tmp/opencode/click-tsan/bin/click tests/configs/smp-*.click` (package there built with `-fsanitize=thread -g -O1 -fPIC -shared`) -- expected `ok` per config, no package frame.
- Byte identity: install `7ac78a9` into a second prefix and run the seven `popstorepush-*` configs from both, with `RandomSeed(SEED 12345)` prepended where absent -- expected: identical stdout, stderr and exit status.
- Negative control: package at `7ac78a9`, same `smp-popstorepush` config -- expected exit 139 and ThreadSanitizer reports naming the element file.

**Observed (2026-11-17, Click master `click-mt` / `click-tsan` prefixes):**
- `make` at `-g -O2 -Wall -Wextra -fPIC -shared`: exit 0, zero warnings; `make install` exit 0.
- `CLICK=/tmp/opencode/click-mt/bin/click bats --tap tests`: `1..169`, 169 ok, no skips.
- `click -j 2 tests/configs/smp-popstorepush.click`: exit 0, 9924 frames (4962 per output), every frame one of the two shapes, both producers on both outputs, no drop line; three runs agreed.
- `tests/tsan-check.sh ... tests/configs/smp-*.click`: `ok` for all four. The same check with the `7ac78a9` package selected fails on `smp-popstorepush.click` with `#0` frames at `diameterpopstorepushavp.cc:27`, `:103` and `diameter.hh`.
- Byte identity: all nine `*popstorepush*.click` configs (the seven named plus the two other `malformed-*` ones) under `RandomSeed(SEED 12345)`: stdout, stderr and exit status identical between `7ac78a9` and this build.
- Negative control on `click-mt`: the `7ac78a9` package with the new config exits 139 on three of three runs, after 101 to 542 frames.
- Plain Click (`click-master`, no multithread): the new test reports `# skip this Click was built without multithread support`.
