---
title: 'Close the six deferred items'
type: 'bugfix'
created: '2026-11-17'
status: 'done'
baseline_revision: 'b32a7d50ffe37481f7837c2c50ce195043a8f25c'
review_loop_iteration: 0
followup_review_recommended: false
context: ['{project-root}/AGENTS.md']
warnings: []
deferred: []
---

<intent-contract>

## Intent

**Problem:** `deferred-work.md` carried six open items from the conformance
delivery: DW-1 (no test pins an M=1 AVP through the package's decode/re-encode),
DW-2 (a repeated keyword silently keeps the last value), DW-3 (no test pins a
`RANDUINT32` draw of zero), DW-4 (Encap and PopStorePush still wrap the
three-octet message Length), DW-5 (AvpEncap wraps the three-octet AVP Length),
and DW-6 (an unbounded `RAND*STRING` count is materialised before the length
guard drops it). Each is either an unprotected path or an observation gap.

**Approach:** close the observation gaps with configs (DW-1, DW-3), add a shared
duplicate-keyword check to each of the four configurable elements (DW-2), add the missing
three-octet ceilings as run-time drops with their own warnings (DW-4, DW-5), and
reject an impossible generator count at configure time (DW-6). The stored AVP is
kept when a PopStorePush push cannot fit, so a later packet can carry it.

## Boundaries & Constraints

**Always:** keep the warnings in the `ELEMENT: dropping packet: ...` style and
name the three-octet field; run the ceiling guards before `put()`/`push()` so a
drop prints no Put advisory and consumes no identifier; keep the accepted bytes
of every existing config unchanged; a repeated keyword fails configuration
naming it (the user's chosen resolution for DW-2); a generator count is capped
at 16,777,184 (16,777,180 with the vendor header); tabs for indentation; the
package stays warning-free at `-Wall -Wextra`.

**Never:** no wire-format change; no new element or argument; no change to the
padding decision, the Identifier counters or the `RAND*` alphabets; do not clear
the PopStorePush store on an overflow; do not add a persistent-state or
cross-reboot claim; keep `click_random()` as the only RNG.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| M=1 survives decode | a 32-octet frame with AVP flags `40` through `DiameterPopStorePushAVP`, twice | first output 20 octets; second 44 octets with the re-encoded AVP still `4000000b` | No error expected |
| Zero draw | `SEED 808357014`, `RANDUINT32 true` | 32-octet frame, AVP Length 12, value `00000000` | No error expected |
| Repeated keyword | any element, a keyword twice | configure failure naming the element and keyword | `the KEYWORD argument is given more than once` |
| Message Length ceiling | Encap payload 16,777,200; PopStorePush stored AVP past the ceiling | packet dropped with the message-Length warning; PopStorePush keeps the store | `dropping packet: ... three-octet ...` |
| AVP Length ceiling | AvpEncap value 16,777,210 | packet dropped with the AVP-Length warning | `dropping packet: the AVP Length would exceed ...` |
| Generator cap | `RANDHEXSTRING 16777185` (or 16777181 with VENDORSPEC) | configure failure naming the argument and the limit | `must not exceed 16777184` / `16777180` |

## Tasks & Acceptance

**Execution:**
- `src/diameterconf.hh` -- the shared duplicate-keyword check; called before
  `Args` in `DiameterEncap`, `DiameterAvpEncap`, `DiameterPushAVP` and
  `DiameterRatedSource`.
- `src/diameterencap.cc`, `src/diameterpopstorepushavp.cc`,
  `src/diameteravpencap.cc` -- the three-octet ceilings, before the extensions.
- `src/diameterpushavp.cc` -- the generator cap in `configure()`.
- `src/*.hh`, `README.md`, `tests/README.md` -- the rules and the config rows.
- `tests/configs/` -- `popstorepush-mandatory`, `push-avp-randuint32-zero`,
  `encap-length-overflow`, `popstorepush-length-overflow`,
  `avp-encap-length-overflow`, `push-avp-randhex-too-large`,
  `push-avp-randhex-too-large-vendor`, `encap-duplicate-code`,
  `rated-source-duplicate-rate`; convert `push-avp-duplicate-octetstring` to a
  configure failure and rebuild `push-avp-length-overflow` around a maximal
  message plus an 8-octet AVP.
- `tests/smoke.bats`, `tests/manpages.bats` -- one test per config and the new
  prose assertions.
- `stories/3-...md`, `stories/4-...md`, `stories/8-...md` -- the closure rows;
  `deferred-work.md` emptied.

**Acceptance Criteria:**
- Given the built package, when the full suite runs, then it exits 0 (162
  tests).
- Given `SEED 808357014`, when `RANDUINT32` runs, then the value is four zero
  octets at AVP Length 12.
- Given an M=1 AVP, when it traverses PopStorePush, then the re-encoded AVP
  keeps flags `40`.
- Given a repeated keyword in any of the four elements, then configuration
  fails naming the keyword.
- Given a payload or AVP whose three-octet Length would wrap, then the packet is
  dropped with the matching warning and no Put advisory.
- Given a generator count past the body limit, then configuration fails naming
  the argument.

## Review Triage Log

### 2026-11-17 — Deferred-work closure

- `[patched]` DW-1, DW-2, DW-3, DW-4, DW-5 and DW-6: each item is closed by the
  config, guard or cap listed above. The pre-change package was used as the
  negative control for the ceilings and the keyword rule.
- `[rejected]` Clearing the PopStorePush store on an overflow: keeping it lets a
  later packet carry the AVP; the drop is reported and the behaviour is
  documented on the page.

## Design Notes

Click hands `configure()` one comma-separated argument per vector element, with
the keyword and value separated by whitespace (`"CODE 280"`), so the duplicate
check reads the first word of each element rather than tokenising the whole
config. No positional argument in this package is a string that could spell a
keyword, so a non-keyword first word is simply skipped and `Args` handles it.

The generator cap is exact for the smallest legal message:
`((0xFFFFFF - 20) & ~3) - header` gives 16,777,184 without the vendor header and
16,777,180 with it, matching the existing `push-avp-length-max` boundary.

## Verification

**Commands:**
- `autoconf && ./configure --with-click=/tmp/opencode/click-mt --prefix=/tmp/opencode/click-mt && make CXXFLAGS="-g -O2 -Wall -Wextra -fPIC -shared" && make install`
- `CLICK=/tmp/opencode/click-mt/bin/click /tmp/opencode/bats-core/bin/bats --tap tests`

## Auto Run Result

Status: done

**Change.** The six deferred items are closed. The new tests pin an M=1 AVP
through decode/re-encode and a zero `RANDUINT32` draw; a shared duplicate-keyword
check refuses a repeated argument in all four configurable elements; Encap,
PopStorePush and AvpEncap drop a packet whose three-octet field would wrap; and
the four `RAND*STRING` counts are capped at configure time.

**Verification (at this tree).**
- `-Wall -Wextra`: clean build, zero diagnostics.
- Full suite: 162/162, exit 0 (10 new tests, one converted).
- Negative control against the pre-change package: Encap emits 16,777,220 octets
  with Length `0x000004`; AvpEncap emits 16,777,220 with Length `0x000002`;
  PopStorePush emits 33,554,404 with a wrapped Length; the duplicate configs keep
  the last value; `RANDHEXSTRING 16777185` configures and drops only at run time.
  The fixed package drops or refuses each at the configured point.
- Installed pages carry the new prose; `tests/manpages.bats` enforces it.

**Residual risks.** The generator cap is a configure-time bound, not a limit on
the incoming message: a count that fits a 20-octet message can still be dropped
at run time when the message in hand is larger. DW-2 now rejects a repeated
keyword everywhere in the package; a config that relied on Click's last-wins
must keep one occurrence.
