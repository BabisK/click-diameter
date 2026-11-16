---
title: 'Story 6: Use Click randomness instead of reseeding the C RNG'
type: 'bugfix'
created: '2026-11-16'
status: 'done'
review_loop_iteration: 0
followup_review_recommended: false
context: ['{project-root}/AGENTS.md']
warnings: ['oversized']
deferred:
  - summary: >-
      `DiameterPushAVP(CODE 264, VENDORSPEC true)` without a `VENDOR` argument
      writes an indeterminate 32-bit Vendor-Id into the AVP: `uint32_t vendorId`
      is left untouched by `Args::read` and passed straight to
      `ah.setVendorId()`.
    evidence: |-
      Pre-existing and untouched by this story. The diff initialized the sibling
      `vendorSpec` because an indeterminate bool decided the AVP's header length,
      which the existing byte assertions can see; `vendorId` has the same class of
      defect but no config exercises the vendor branch with VENDORSPEC alone, so
      fixing it would be new argument-validation policy. A config passing
      `VENDORSPEC true` without `VENDOR`, plus a decision between defaulting to 0
      and rejecting the pair, would settle it.
    location: >-
      src/diameterpushavp.cc:80
    severity: medium
baseline_revision: '2b46a644ed6b92a892fe2b40af476b2c5734ca1f'
---

<intent-contract>

## Intent

**Problem:** `DiameterEncap`, `DiameterPushAVP` and `DiameterRatedSource` each call `srand(time(NULL))` in `configure()` and draw every random field from `rand()`, so they reseed the process-wide C library RNG from the wall clock and no run can be reproduced from Click's seed (F-11). A `RandomSeed(SEED n)` in the configuration has no effect on them, and they also override the seed for any other element sharing the process.

**Approach:** Delete the three `srand` calls and draw from `click_random()` instead of `rand()`. The elements only consume Click's stream, which `RandomSeed(SEED n)` pins at configure time, so two runs at the same seed emit identical octets.

## Boundaries & Constraints

**Always:** Random values still vary per message and per run when no seed is set; the drawing sites, their modulo arithmetic, and the value ranges stay as they are, so only the source of the stream changes. Element names, arguments, port counts and every existing `.click` config keep working; tabs, zero warnings at `-Wall -Wextra`; `src/diameter.hh` gains nothing.

**Never:** No element calls `click_srandom`/`click_random_srandom` — reseeding inside an element is the defect, not the fix. No new element, argument, port or `SEED` argument on these elements; no change to what is random (the `hbh`/`e2e` identifiers and the `RAND*` values) or to the alphabets story 4 fixed; no `AC_INIT`, include-guard, `<iostream>` or fork work (story 8). Do not edit `SPEC.md` or `findings.md`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| ENCAP_SEEDED | `RandomSeed(SEED 12345)`, two `de ad be ef` payloads into `DiameterEncap(CODE 280, REQUEST true)` | Two 24-octet frames; a second run more than a second later prints identical octets; the two `hbh`/`e2e` pairs differ from each other | No error expected |
| RATED_SEEDED | Same seed, `DiameterRatedSource(CODE 280, REQUEST true, APPID 42, LIMIT 2, STOP true)` | Two 20-octet frames; identical across the two runs; identifiers differ within the run | No error expected |
| PUSH_AVP_SEEDED | Same seed, two header-only requests into `DiameterPushAVP(CODE 264, RANDHEXSTRING 8)` | Two 36-octet frames; identical across the two runs; the two 8-character values differ | No error expected |
| SEEDED_VS_OTHER | `RandomSeed(SEED 1)` and `RandomSeed(SEED 2)` in the same second | The two seeds produce different octets — the seed, not the clock, decides | No error expected |
| SOURCE_SCAN | `src/` after the change | No bare `srand`, `rand`, `srandom` or `random` call remains | No hits |

</intent-contract>

## Code Map

- `src/diameterencap.cc:16` -- `srand(time(NULL))` in `configure`; `:57-58` -- `dh.setHbh(rand())` / `setE2e(rand())` in `simple_action`. The file includes no `click/glue.hh`, so add it for `click_random()`.
- `src/diameterratedsource.cc:27` -- the `srand` call; `:97-98` (push path in `run_task`) and `:128-129` (pull path) -- the two `hbh`/`e2e` draws. `<click/glue.hh>` is already included at `:14`.
- `src/diameterpushavp.cc:75` -- the `srand` call; `:44,50,56,62` -- one draw per alphabet inside `randString()`; `:123` -- the `RANDUINT32` draw in `simple_action`. `<click/glue.hh>` is already included at `:10`.
- `src/diameter.hh` -- read-only for this story: `setHbh`/`setE2e` take the draw unchanged, `encode` writes it into the header.
- `tests/smoke.bats:25-31` -- `run_click` takes a bare config name and prefixes `configs/`; `:34-36` -- `expect`. The seeded tests need a run of a generated config path, so split `run_click` into `run_config PATH` plus a thin wrapper; the source scan needs `$BATS_TEST_DIRNAME/../src`.
- `tests/configs/rated-source.click`, `push-avp-rand.click`, `encap.click` -- the unseeded configs whose identifiers stay regexed; they are the regression set for "no byte outside the identifiers moves".
- `tests/README.md:18-28` -- the random-identifier prose to extend; `:51-124` -- the config table to add three rows to.
- `README.md:205-239` -- the "Flag policy" section to sit beside and the "Known limitations" F-11 bullet to remove.
- `_bmad-output/specs/spec-diameter-package-hardening/findings.md:80-84` -- read-only F-11 evidence; its `src/diameterinfinitesource.cc` does not exist, the third caller is `diameterencap.cc`.

## Tasks & Acceptance

**Execution:**
- `src/diameterencap.cc` -- delete the `srand` line, draw both identifiers with `click_random()`, include `<click/glue.hh>` -- F-11 for the element that frames payloads.
- `src/diameterratedsource.cc` -- delete the `srand` line and replace all four draws -- F-11 for the generated message.
- `src/diameterpushavp.cc` -- delete the `srand` line and replace the five draws -- F-11 for the generated values.
- `tests/configs/randomness-encap.click`, `randomness-rated-source.click`, `randomness-push-avp.click` -- `RandomSeed(SEED 12345)` plus two packets each, one `Print` label per config -- CAP-6 byte assertions.
- `tests/smoke.bats` -- split `run_click` into `run_config PATH` and a wrapper, then one test per seeded config that runs it, checks the two packets differ, rewrites the seed in a copy under `$BATS_TEST_TMPDIR` and requires different octets, sleeps 1.1 s, reruns and requires identical output; plus a test that greps `src/` for a bare C RNG call -- a wall-clock, frozen or seed-ignoring stream fails the run.
- `tests/README.md`, `README.md` -- the three config rows, a "Randomness" section naming `RandomSeed` as the way to reproduce a run, and the F-11 limitation removed -- the docs describe the tree as it now behaves.

**Acceptance Criteria:**
- Given `RandomSeed(SEED 12345)` and `DiameterEncap`, when the config is run twice more than a second apart, then both runs print identical octets (CAP-6, F-11).
- Given the same seed with `DiameterRatedSource` and with `DiameterPushAVP(RANDHEXSTRING 8)`, when each runs twice that way, then each pair of runs is identical.
- Given two packets in one seeded run, when the random fields are compared, then they differ — the stream advances rather than repeating one value.
- Given `RandomSeed(SEED 1)` and `RandomSeed(SEED 2)` through the same element, when each runs, then the octets differ — the seed, not the clock or a constant, decides.
- Given `src/`, when it is scanned, then no bare `srand`, `rand`, `srandom` or `random` call remains.
- Given the unseeded configs, when the suite runs, then every existing byte expectation is unchanged and their identifier regexes still match.
- Given the package on Click master, when built at `-Wall -Wextra` and `bats --tap tests` runs, then zero warnings and every test passes.

## Spec Change Log

## Review Triage Log

### 2026-11-16 — Review pass
- verdicts: 30 findings — high 0, medium 3, low 24, false 3
- findings:
  - `[low]` `[reject]` (blind) `bool vendorSpec = false` is an uncatalogued fix outside F-11 — real that the story does not name it, but the absent-`VENDORSPEC` shape is already pinned byte for byte by `push-avp.click` (32 octets, 8-octet AVP header), so a regression fails there; the reason for the initialization and the excursion are recorded in this log and `## Auto Run Result`, and no code change remains.
  - `[medium]` `[defer]` (blind) `vendorId` at `src/diameterpushavp.cc:80` is still indeterminate when `VENDORSPEC true` arrives without `VENDOR` — real, pre-existing and untouched by this story; recorded in `deferred`.
  - `[medium]` `[patch]` (blind) the source scan cannot see `click_srandom`/`click_random_srandom`, which the Never clause bans — real; the pattern, the test name, its comment and `tests/README.md` now cover all six calls.
  - `[low]` `[patch]` (blind) the scan passes when `src/` is unreadable because `|| true` swallows grep's exit 2 — real; the test now asserts the directory exists and maps exit 1 to pass and exit 2 to failure.
  - `[low]` `[patch]` (blind) the changed `RANDUINT32` draw and the `pull()` draws have no test — real; `randomness-push-avp-uint32.click` and `randomness-rated-source-pull.click` with their `expect_seeded` tests now cover both.
  - `[low]` `[reject]` (blind) nothing asserts that an unseeded run still varies — the only available assertion is "two unseeded runs differ", which can fail by chance and guards a mechanism Click's own per-router seeding already owns; every other byte of those configs is pinned, so a frozen stream could not pass them silently.
  - `[low]` `[patch]` (blind) the seed rewrite is pinned to the literal `SEED 12345` and no-ops silently if a config's seed changes — real; `sed -E` now matches any numeric seed and a `cmp -s` guard names the rewrite instead of blaming the element.
  - `[low]` `[reject]` (blind) `expect_seeded` proves the two lines differ, not which fields — the matrix asks for different frames, every fixed field is pinned byte for byte by the unseeded configs, and a field-aware comparison would add a per-config expression for a second-packet-only corruption nothing suggests.
  - `[low]` `[patch]` (blind) the README explains the seed through configure order and omits its process-global scope — real; rewritten to call `RandomSeed` Click's per-router seed replacement, state that it pins every `click_random()` consumer and that its position does not matter, and add the single-thread assumption.
  - `[low]` `[patch]` (blind) eleven unseeded configs and two test comments still describe their identifiers as "random (F-11)" — real; they now say the config sets no seed, so the identifiers vary per run and the test regexes them.
  - `[low]` `[patch]` (blind) `tests/README.md` documents three of the four new tests, never names `expect_seeded` and contradicts itself about regex versus pinned — real; all five seeded configs and the scan are documented, the helper is named beside `expect_drop` and `expect_configure_failure`, and the two cases are separate sentences.
  - `[low]` `[patch]` (blind) the suite's new bats 1.5 and `RandomSeed` requirements are undocumented — real; both are stated in `tests/README.md` and the `smoke.bats` header.
  - `[low]` `[reject]` (blind) the seeded configs clone the unseeded ones with no cross-reference — each carries its own comment and `Print` label and is guarded by its own test, so a divergent argument fails that test; a twin note would be prose with nothing behind it.
  - `[low]` `[reject]` (blind) nothing records F-11's closure — this log and `## Auto Run Result` record the deleted `srand` calls, the twelve rewritten draws and the `vendorSpec` decision; `findings.md` stays the epic's immutable evidence record by design.
  - `[medium]` `[defer]` (edge) `vendorId` is uninitialized when only `VENDORSPEC` is given — same defect and route as the first `vendorId` row.
  - `[low]` `[patch]` (edge) grep exit 2 is mistaken for a clean scan — same defect and route as the unreadable-`src` row.
  - `[low]` `[patch]` (edge) alternative C RNG callers (`rand_r`, `drand48`, `arc4random`) pass the scan — the bad outcome does not follow: F-11 and the Never clause name `srand`, `rand` and the `click_*` reseeds only, and the test name and comment now state exactly that scope, so it no longer claims to police the whole C library.
  - `[false]` `[reject]` (edge) a failing `sleep 1.1` passes silently and lets a wall-clock stream through — refuted: bats runs test bodies under `set -e`, so an unsupported fractional sleep fails the test loudly.
  - `[low]` `[patch]` (edge) a multi-threaded router's interleaving breaks seeded reproduction — real as an overclaim in new README text; the section now states that reproduction assumes a single thread or a fixed draw order.
  - `[low]` `[patch]` (verification gap) the `RANDUINT32` branch is unverified — same route as the unexercised-draw row; the new config and test close it.
  - `[low]` `[patch]` (verification gap) `DiameterRatedSource`'s `pull()` draws never execute in the suite — same route; the `Unqueue` config and test close it.
  - `[medium]` `[defer]` (verification gap) `vendorId` is initialized on one side of the pair only — same defect and route as the first `vendorId` row.
  - `[low]` `[reject]` (verification gap) the `vendorSpec` change is not named in the story — same row as the first `vendorSpec` finding.
  - `[low]` `[reject]` (intent) the process-global clobbering clause has no test — the elements no longer seed at all and the scan now bans every reseed call, so a reintroduction fails the suite; a second-consumer config would assert Click's own stream rather than this change.
  - `[low]` `[reject]` (intent) "identical octets" is asserted as identical `Print` lines — same row as the lines-versus-fields finding.
  - `[low]` `[reject]` (intent) the unseeded per-run half of the Always clause is unasserted — same row as the unseeded-variation finding.
  - `[false]` `[reject]` (intent) the unchanged-value-range claim cannot be observed by a test — refuted: `click_random()` is `random()` on the userlevel build with `CLICK_RAND_MAX == RAND_MAX`, so `rand()` and `click_random()` share the `[0, 2^31-1]` domain; the claim is settled by inspection of `click/glue.hh`, not by an assertion.
  - `[low]` `[reject]` (intent) the `vendorSpec` change sits on a surface no reading covers — same row as the first `vendorSpec` finding.
  - `[low]` `[patch]` (intent) `sprint-status.yaml` still reads `backlog` while the story is in review — real; set to `review` and `last_updated` refreshed.
  - `[false]` `[reject]` (intent) the `run_config` split puts every existing test at risk — refuted: `run_click` is now a one-line wrapper over `run_config`, no existing test body changed, and all 67 pre-existing tests pass in this run.

## Design Notes

- **`click_random()` is the seeded stream; `rand()` only shares its state on Linux.** `Router::initialize` calls `click_random_srandom()` before configuring elements, and `RandomSeed(SEED n)` replaces that seed at `CONFIGURE_PHASE_FIRST`. The elements then called `srand(time(NULL))` in their own `configure`, overwriting the seed, which is why `SEED 1` and `SEED 2` produced the same bytes in the probe.
- **Deleting `srand` is the fix, not swapping it.** Calling `click_srandom()` in an element would re-break reproducibility the same way: one element would force every later draw in the graph into its own stream. These elements only consume.
- **`findings.md` mis-names the third caller.** F-11 lists `src/diameterinfinitesource.cc`, which does not exist; `grep -nE '\bs?rand\b|\bs?random\b'` over `src/` finds the 14 call sites in `diameterencap.cc`, `diameterpushavp.cc` and `diameterratedsource.cc` — three elements, as the epic says.
- **The test sleeps between runs.** Two wall-clock-seeded runs that land in the same second are identical, so a same-second repeat would pass before the fix; each seeded test reruns its config after 1.1 s.
- **The stream domain is unchanged.** `click_random()` is `random()` on the userlevel build with the same `CLICK_RAND_MAX`, so `% (sizeof(alphabet) - 1)` keeps its distribution and `setHbh`/`setE2e` keep their range; only the identifiers and generated values move, and only when a seed is pinned.
- **Pre-fix probes** (2026-11-16, `$HOME/click-master`, this baseline): `RandomSeed(SEED 1)` and `RandomSeed(SEED 2)` through `DiameterEncap` in the same second both print `33d8b7e4 2e0b2343`, while `SEED 1` run 1.1 s later prints `61411a1f 626785a3`. `DiameterRatedSource` and `DiameterPushAVP(RANDHEXSTRING 8)` behave the same way. Reproduce these before editing.

## Verification

**Commands:**
- Export the working tree to WSL with LF endings; `autoconf && ./configure --with-click=$HOME/click-master --prefix=$HOME/click-master && make && make install` -- expected: zero warnings, `diameter.uo` installed.
- `g++ -fsyntax-only -I$HOME/click-master/include -W -Wall -Wextra src/*.cc` -- expected: no output.
- `CLICK=$HOME/click-master/bin/click bats --tap tests` -- expected: every test passes, including the three seeded pairs and the unchanged regexed expectations.
- Install into the AddressSanitizer prefix and run the full suite -- expected: exit 0, no sanitizer report.

**Manual checks (if no CLI):**
- Run `randomness-encap.click`, wait, run it again, and diff the two outputs; run the same pair without `RandomSeed` and confirm they differ.

## Auto Run Result

Summary: the package now draws its random values from Click's stream instead of reseeding the C library RNG from the wall clock. `DiameterEncap`, `DiameterPushAVP` and `DiameterRatedSource` shed their `srand(time(NULL))` calls and draw all twelve sites through `click_random()`, so `RandomSeed(SEED n)` — which replaces the seed Click sets once per router — decides the stream: two runs of the same config emit identical octets, two seeds emit different ones, and successive packets still differ because the stream advances. Five seeded configs and one source scan pin that contract, and the harness fails a clock-seeded, frozen or seed-ignoring stream. One incidental fix was forced: `DiameterPushAVP::configure` read `vendorSpec` from an uninitialized stack slot, and removing the `srand` call changed what that slot held, so every `DiameterPushAVP` config without `VENDORSPEC` silently grew a vendor header; it is now initialized to its documented `false` default, which `push-avp.click` pins at 32 octets.

Files changed:
- `src/diameterencap.cc` — `srand` deleted, both identifiers drawn with `click_random()`, `<click/glue.hh>` added.
- `src/diameterratedsource.cc` — `srand` deleted, all four draws in `run_task` and `pull` rewritten.
- `src/diameterpushavp.cc` — `srand` deleted, the four alphabet draws and the `RANDUINT32` draw rewritten; `vendorSpec` initialized.
- `tests/configs/randomness-encap.click`, `randomness-rated-source.click`, `randomness-rated-source-pull.click`, `randomness-push-avp.click`, `randomness-push-avp-uint32.click` — `RandomSeed(SEED 12345)` and two packets each, one per drawing path.
- `tests/smoke.bats` — `run_config` split out of `run_click`; `expect_seeded` helper; five seeded tests; the `randomness-source` scan that fails on any bare or `click_*` reseed call and on an unreadable `src/`; header notes.
- `tests/README.md`, `README.md` — the seeded config rows and helper documented, a "Randomness" section naming `RandomSeed` and its process-global scope, and the F-11 limitation removed.
- `tests/configs/*.click` — eleven comments reworded from "random (F-11)" to "this config sets no seed".
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — story 1-6 moved to `review`.

Review findings breakdown: 30 findings — high 0, medium 3, low 24, false 3. Patched: 10 entries, 1 medium and 9 low — the source scan now bans the `click_srandom`/`click_random_srandom` reseeds the Never clause names and fails when it cannot read `src/`; the scan's name and comment state exactly which calls it bans; a seeded `RANDUINT32` config and a seeded `Unqueue` config close the two drawing paths the first round never executed; the seed rewrite matches any numeric seed and is checked with `cmp -s`; the README states the real mechanism, the seed's process-global scope and its single-thread assumption; the eleven stale `F-11` comments, the `tests/README.md` prose, requirements and helper naming, and `sprint-status.yaml` corrected. Deferred: 1 (the sibling `vendorId` is still indeterminate when `VENDORSPEC true` arrives without `VENDOR`). Rejected: 16 — the `vendorSpec` initialization is uncatalogued but already pinned by `push-avp.click` and now recorded here; the unseeded per-run and lines-versus-fields assertions would buy a probabilistic test or a per-config expression for corruptions nothing suggests; the cloned configs, the closure record and the process-global test would add prose or assert Click's own stream; the alternative RNG names and the value-range claim are outside F-11's scope, the range verified from `click/glue.hh` instead; the `sleep` claim is disproved by `set -e`, and the `run_config` split is a semantics-preserving wrapper over which all 67 pre-existing tests pass.

Follow-up review recommendation: false. One patched entry was medium and none was high, so a first pass has converged.

Verification performed (WSL Ubuntu 26.04, GCC 15.2, against Click 2.1 built from upstream master `9197a594b`):
- Pre-fix probes reproduced F-11: `RandomSeed(SEED 1)` and `RandomSeed(SEED 2)` through `DiameterEncap` in the same second both printed `33d8b7e4 2e0b2343`, while `SEED 1` run 1.1 s later printed `61411a1f 626785a3`; `DiameterRatedSource` and `DiameterPushAVP(RANDHEXSTRING 8)` behaved the same way.
- Fresh LF export of the final tree: `autoconf && ./configure --with-click=$HOME/click-master --prefix=$HOME/click-master && make && make install` — zero compiler warnings, `diameter.uo` and the elementmap installed.
- `g++ -fsyntax-only -I$HOME/click-master/include -W -Wall -Wextra src/*.cc` — no output, exit 0.
- `CLICK=$HOME/click-master/bin/click bats --tap tests` — 73/73 pass, including the five seeded tests and the unchanged 67.
- AddressSanitizer: the package rebuilt and installed into the `$HOME/click-asan` prefix, the full suite under `ASAN_OPTIONS=detect_leaks=0` — 73/73 pass, exit 0, no sanitizer report.
- Negative check: the baseline package installed into the same prefix turns all five seeded tests red with `expected a different seed to print different octets`; the source scan stays green because it reads the fixed tree, which is what it is for.
- Matrix audit: ENCAP_SEEDED (test 45), RATED_SEEDED (46), PUSH_AVP_SEEDED (47), SEEDED_VS_OTHER (asserted inside 45-49 by the rewritten-seed run) and SOURCE_SCAN (73) each ran and passed.

Residual risks: `linuxmodule` and `bsdpkg` cannot be built on this host, so their compilability rests on the change adding only a Click header and using `click_random()`, which every target provides. The seeded tests sleep 1.1 s each, adding about 5.5 s to the suite, and they depend on Click's `RandomSeed` test element and bats 1.5's `BATS_TEST_TMPDIR`, both documented. Reproduction assumes a single-threaded router, where draw order is fixed; `vendorId` remains indeterminate in the vendor branch (deferred), and `findings.md` still describes F-11 as open because it is the epic's immutable evidence record.
