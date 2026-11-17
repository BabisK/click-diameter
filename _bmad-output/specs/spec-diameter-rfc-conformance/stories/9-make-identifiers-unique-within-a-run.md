---
title: 'Make identifiers unique within a run'
type: 'bugfix'
created: '2026-11-17'
status: 'done'
review_loop_iteration: 0
followup_review_recommended: false
baseline_revision: 'ec0b5f0bf140839b87875a33165b4914cf5e66df'
context: ['{project-root}/AGENTS.md']
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** Both writers stamp fresh `click_random()` draws into every message: `DiameterEncap` at `src/diameterencap.cc:70-71` and `DiameterRatedSource` in both `run_task()` (`src/diameterratedsource.cc:103-104`) and `pull()` (`:134-135`). At 1 000 messages per second a four-minute window holds 240 000 messages, and 32 random bits cannot keep that many values distinct. Measured on the installed baseline with `RandomSeed(SEED 12345)`, 240 000 messages produced 11 duplicate hop-by-hop and 7 duplicate end-to-end identifiers from `DiameterEncap`, 17 and 13 from `DiameterRatedSource`, and 37 and 30 messages whose two identifiers were equal. A peer is entitled to treat a repeated identifier as a retransmission or a replay (RFC 6733 section 3, finding A-7, CAP-4).

**Approach:** Give each writer one counter per identifier, seeded once in `initialize()` from two `click_random()` draws and advanced by one for every message actually emitted. Each field is then unique for the first 2^32 messages of a run. The End-to-End field keeps RFC 6733 section 3's twelve/twenty split: its high-order 12 bits are the coarse epoch that advances when the low-order 20-bit counter wraps, so the RFC's time slot is carried by a deterministic epoch rather than by the wall clock. Reading the clock is excluded because two runs with the same `RandomSeed` must stay byte-identical (SPEC CAP-4 and this story's criterion), so the seed alone decides where both sequences start. Counters are atomic and `DiameterRatedSource` encodes a per-message header copy, so the change adds no shared per-packet write.

## Boundaries & Constraints

**Always:** Both identifiers come only from the seed and the per-message count after initialization; a seeded run reproduces byte for byte, including a rerun more than a second later. Each field is unique across the first 2^32 emitted messages. Counters advance once per emitted message, not per token-bucket refusal, so push and pull share one sequence per element. In a single-threaded run the two identifiers of one message differ, even when the two seed draws coincide. The counters are atomic, because one element may be fed from several router threads. The first message of `randomness-encap` and `randomness-rated-source` keeps the bytes it emits today (today's first two draws become the seed draws). Tabs for indentation; the package stays warning-free at `-Wall -Wextra`.

**Never:** No wall-clock, process-time or `Timestamp` input in the identifier path (`time`, `gettimeofday`, `Timestamp::now`); no `srand`, `rand`, `srandom`, `random`, `click_srandom` or `click_random_srandom`. No new or changed element argument; no change to frame layout, Length, flags, Command Code, App-Id, AVP handling or `DiameterPushAVP`'s `RAND*` generators. No persistent state and no across-reboot claim; a counter restarting at a new seed is the whole guarantee. No lock, semaphore or blocking call, and no edit to `.github/workflows/`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Encap, 240 000 messages | `RandomSeed(SEED 12345)`, `InfiniteSource(LIMIT 240000)`, `DiameterEncap` | 240 000 frames, 240 000 distinct hop-by-hop and 240 000 distinct end-to-end values | No error expected |
| RatedSource at the story's rate | `RandomSeed(SEED 12345)`, `RATE 1000, LIMIT 240000` under `--simtime` | the same two uniqueness counts, reached through the token bucket | No error expected |
| Same-seed replay | either config run twice | the two outputs are byte-identical | No error expected |
| Seed draws coincide | the two `click_random()` draws are equal | the second start is bumped, so both fields still advance and one message never carries two equal identifiers | No error expected |
| Pull path | `Unqueue` forcing `DiameterRatedSource::pull()` | identifiers come from the same counter as the task path and advance once per returned packet | No error expected |
| Pre-change baseline | the installed `ec0b5f0` package, same configs | duplicates in both fields (11/7 Encap, 17/13 RatedSource) and equal pairs (37/30) | Negative control |

</intent-contract>

## Code Map

- `src/diameter.hh:7-21` -- the shared size enum and the only place both writers already share code; add `#include <click/atomic.hh>` beside `<stdint.h>` and the counter class after the enum. `DiameterHeader`'s `setHbh()`/`setE2e()` at `:79-99` take a `uint32_t`, so no encoder change is needed.
- `src/diameterencap.cc:63-78` -- `simple_action()`: `:69` copies the configured header, `:70-71` are the two per-packet draws to replace. The element has no `initialize()` today.
- `src/diameterencap.hh:21-27` -- the `=d` sentence that promises a draw "for each packet"; `:84-99` the class body, where `initialize()` and the counter member go.
- `src/diameterratedsource.cc:74-82` -- `initialize()`, the only hook that runs after every element's `configure()`, so `RandomSeed` has already applied its seed wherever it sits in the config. `:103-104` (`run_task`) and `:134-135` (`pull`) are the four draws to replace; `:107` is the token-bucket test, so the counter steps belong inside the success branch. `:112` and `:144` encode `dh`; copy it to a local first, as `DiameterEncap` already does.
- `src/diameterratedsource.hh:26-31` -- the `=d` sentence to rewrite; `:108-145` the class body, where `initialize()` exists at `:118` and `dh` at `:138`.
- `~/git/click/elements/test/randomseed.cc:38-50` -- read-only evidence: `RandomSeed` calls `click_srandom()`/`click_random_srandom()` in `configure()`, so a seed drawn in any `initialize()` is already reproducible.
- `tests/smoke.bats:60-104` -- `run_config`/`run_click` and the timeout contract; add a `--simtime` sibling. `:133-168` `expect_seeded` sleeps 1.1 s and requires a byte-identical rerun, which a clock component would break at a quantum boundary. `:838-856` the five `randomness-*` tests; `:1064-1077` the `randomness-source` scan that already bans every reseed form. `:9-58` the coverage comment.
- `tests/configs/randomness-encap.click`, `tests/configs/randomness-rated-source.click`, `tests/configs/rated-source.click` -- the seeded 20/24-octet shapes the new configs copy; `Print(..., MAXLENGTH 20, CONTENTS HEX)` puts hop-by-hop at field 7 and end-to-end at field 8.
- `tests/manpages.bats:95-131` -- `expect_element_page` and the two writer pages; `:160-180` shows the flattened-description prose assertion style.
- `tests/README.md:26-27`, `:62-75` -- the seeded-test and identifier prose; `:296-305` the config table rows.
- `README.md:179-180` -- the two element-reference rows; `:283-298` the "Randomness" section that currently claims every random field is drawn per packet.
- `/tmp/opencode/click-mt` -- Click 2.1 installed prefix carrying the `ec0b5f0` package; `/tmp/opencode/bats-core/bin/bats` is bats-core 1.14.

## Tasks & Acceptance

**Execution:**
- `src/diameter.hh` -- include `<click/atomic.hh>` and add `DiameterIdentifierCounter` whose constructor zeroes both `atomic_uint32_t` fields, with a `seed(uint32_t hbhStart, uint32_t e2eStart)` that bumps `e2eStart` when the starts are equal, and `nextHbh()`/`nextE2e()` returning `fetch_and_add(1)` -- one place documents the RFC rule and both writers share it.
- `src/diameterencap.cc` -- add `initialize()` that draws `hbhStart` and `e2eStart` into named locals (not two arguments of one call, whose evaluation order is unspecified), seeds the counter and returns 0, and replace the two `click_random()` calls in `simple_action()` with `ids.nextHbh()`/`ids.nextE2e()` -- the data path stops touching the RNG.
- `src/diameterencap.hh` -- declare `int initialize(ErrorHandler *) CLICK_COLD;`, add the counter member beside the configuration-only `dh`, and rewrite the `=d` identifier sentence: seeded once from `click_random()`, advanced per message, unique for 2^32 messages within a run, reproduced by `RandomSeed`, no across-reboot claim.
- `src/diameterratedsource.cc` -- seed the counter at the top of `initialize()`; in `run_task()` and `pull()` copy `dh` into a local header, stamp it with the two counter values only inside the token-bucket success branch, and encode the local -- closes the shared-header write while the identifier code moves.
- `src/diameterratedsource.hh` -- add the counter member and rewrite the `=d` identifier sentence the same way, naming the pull path.
- `tests/configs/identifiers-encap-unique.click` -- `RandomSeed(SEED 12345)`, `InfiniteSource(DATA \<de ad be ef>, LIMIT 240000, STOP true)` through `DiameterEncap` to `Print(ids, MAXLENGTH 20, CONTENTS HEX)` -- the 240 000-message uniqueness repro for the first writer.
- `tests/configs/identifiers-rated-source-unique.click` -- the same seed and count at `RATE 1000` through `DiameterRatedSource` -- the story's rate-shaped repro for the second writer.
- `tests/configs/randomness-encap.click`, `randomness-rated-source.click`, `randomness-rated-source-pull.click` -- rewrite the "draw twice" comments to say the counters start from the seed and advance per message -- the comments must not describe a generator the code no longer uses.
- `tests/smoke.bats` -- add `run_click_simtime` and `expect_unique_identifiers CONFIG COUNT`, which requires COUNT printed lines, COUNT distinct field-7 values, COUNT distinct field-8 values, no line with equal fields, and a byte-identical second run; add one test per config and extend the header comment.
- `tests/manpages.bats` -- add one test requiring both writer pages to name the seeding rule (`seeded once from click_random()`) and in-run uniqueness in their DESCRIPTION -- the page is the only place a caller learns the guarantee.
- `tests/README.md`, `README.md` -- describe the counters, the `--simtime` runs, the two configs and what they prove, and correct the "every random field is drawn per packet" prose; extend the config table and the two element rows.

**Acceptance Criteria:**
- Given the rebuilt package, when `CLICK=PREFIX/bin/click bats --tap tests` runs, then it exits 0 with every existing expectation unchanged, including the five `randomness-*` tests and the `smp-*` tests.
- Given `identifiers-encap-unique.click` under `--simtime`, when it runs, then it prints exactly 240 000 frames with 240 000 distinct hop-by-hop and 240 000 distinct end-to-end values and no frame whose two identifiers are equal.
- Given `identifiers-rated-source-unique.click` (`RATE 1000, LIMIT 240000`) under `--simtime`, when it runs, then the same three counts hold.
- Given either config, when it is run a second time with the same `RandomSeed`, then the second output is byte-identical to the first.
- Given the installed `ec0b5f0` package, when the two new helper invocations run, then both fail on duplicates in each field (11/7 Encap, 17/13 RatedSource) with 37/30 equal pairs -- the negative control.
- Given the installed prefix, when `tests/manpages.bats` runs, then both writer pages state the seeded-counter rule and in-run uniqueness.
- Given any committed `encap-*`, `rated-source*` or `randomness-*` config, when it runs, then every field other than the counters is unchanged, and the first frame of `randomness-encap` and `randomness-rated-source` keeps the bytes `SEED 12345` produces today.

## Spec Change Log

## Review Triage Log

## Design Notes

The repro is deterministic, not probabilistic: with `RandomSeed(SEED 12345)` the baseline emitted the same 240 000 messages twice, and `sort -u` over field 7 and field 8 counted 239 989/239 993 distinct values for `DiameterEncap` and 239 983/239 987 for `DiameterRatedSource`, with 37 and 30 frames carrying equal identifiers. So the pre-change build fails the new configs every time rather than once in a while.

`RATE 1000` with `LIMIT 240000` is four minutes of real time. Click's `--simtime` runs the same token-bucket schedule as fast as the machine allows (measured 0.7 s cold for this config, 0.5 s for the un-rated Encap config), so the test keeps the story's rate instead of weakening it. Both helper runs stay inside the 10 s `click_timeout`.

Seeding belongs in `initialize()`, not `configure()`: Click configures every element before initializing any, so `RandomSeed`'s `configure()` has applied the seed regardless of where its statement sits. Seeding in `configure()` would make the draw order depend on statement order. Drawing into named locals also avoids unspecified argument-evaluation order in `seed(click_random(), click_random())`.

A wall-clock twelve-bit component was considered and rejected: it would make `expect_seeded`'s 1.1 s rerun and this story's byte-identity criterion depend on whether a quantum boundary fell between the runs. The high 12 bits of the End-to-End counter advance when the low 20 wrap, which keeps RFC 6733 section 3's field shape, and the seed decides the starting epoch, so the RFC's time slot is present without a clock input.

The equal-seed-draw branch cannot be reached from a config -- it needs the two draws to coincide, 1 in 2^32, and a config cannot force a specific draw -- so it is covered by inspection and by the fact that both sequences advance regardless; if it did fire, the bump keeps the two starts distinct without changing either field's uniqueness.

The counters are atomic because `tests/configs/smp-encap.click` feeds one `DiameterEncap` from two threads; a plain field would race and could hand two frames the same value. `DiameterRatedSource` has one task, but its `dh` was still written per packet, so the header became a local copy in the same pass -- the shape story 1 gave the other three writers, and the reason story 1's contract left this element to stories 8 and 9.

## Verification

**Commands:**
- `autoconf && ./configure --with-click=/tmp/opencode/click-mt --prefix=/tmp/opencode/click-mt && make CXXFLAGS="-g -O2 -Wall -Wextra -fPIC -shared" && make install` -- expected: builds with no diagnostics under `-Wall -Wextra`
- `CLICK=/tmp/opencode/click-mt/bin/click /tmp/opencode/bats-core/bin/bats --tap tests` -- expected: every test passes, including the two new configs
- `CLICK=/tmp/opencode/click-mt/bin/click /tmp/opencode/bats-core/bin/bats --tap --filter 'identifiers|randomness' tests` -- expected: the two new tests and the five seeded tests pass
- Negative control: `CLICKPATH=/tmp/opencode/s8b-base-prefix/lib /tmp/opencode/click-mt/bin/click --simtime tests/configs/identifiers-encap-unique.click` (and the RatedSource config) -- expected: the helper reports the duplicate counts measured above
- Mutation checks: revert `ids.nextHbh()` to `click_random()` -- expected: the Encap uniqueness test fails; seed only one field -- expected: that field's count fails; seed in `configure()` instead of `initialize()` with `RandomSeed` placed after the writer -- expected: the replay test fails; remove the helper's second run -- expected: the byte-identity assertion is no longer exercised; restore and rerun green
- Installed pages: `man -M /tmp/opencode/click-mt/share/man DiameterEncap` and `DiameterRatedSource` -- expected: both state the seed-once/unique-within-a-run rule

**Environment:** `/tmp/opencode/click-mt` is Click 2.1 built with `--enable-user-multithread` and currently carries the `ec0b5f0` package; a plain `make install` overwrites it. `/tmp/opencode/s8b-base-prefix` holds the pre-change package for the negative control.

## Auto Run Result

Status: done

Planning halted as directed after the ready-for-development gate; no implementation was started.
