---
title: 'Story 5: Set request and answer flags per RFC 6733'
type: 'bugfix'
created: '2026-11-16'
status: 'in-review'
review_loop_iteration: 0
followup_review_recommended: false
context: ['{project-root}/AGENTS.md']
warnings: ['oversized']
deferred:
  - summary: >-
      The T bit is unchecked on both paths this story touches, so an answer can
      carry T: `DiameterEncap(REQUEST false, RETRANSMITED true)` configures and
      emits flags `10`, and flipping a request that carries T yields an answer
      that keeps it.
    evidence: |-
      RFC 6733 section 3 says T "MUST NOT be set in answer messages", but the
      story's intent names only E on requests and P on answers, and no finding
      catalogues T. Both behaviours predate this change: `DiameterEncap` has
      always accepted `RETRANSMITED` without checking `REQUEST`, and
      `DiameterFlipRequest` has only ever toggled R. Rejecting the pair is the
      same one-line guard the P rule uses, but which bits the package polices
      is policy the intent sets, and it named two.
    location: >-
      src/diameterencap.cc:37
    severity: medium
  - summary: >-
      Flipping an error answer back into a request keeps E set, so the element
      can emit a request with E, which RFC 6733 section 3 and section 7.2
      forbid.
    evidence: |-
      An answer with flags `20` flips to `a0`. Pre-existing: the answer-to-
      request branch has never touched E, and the story's intent scopes its E
      clause to generated requests, so adding an E rule to that branch is
      behaviour the intent does not ask for. The request it produces is a
      synthetic message whose flags came from an answer, so the fix needs a
      decision on whether a flip sanitizes every bit the new type forbids.
    location: >-
      src/diameterfliprequest.cc:36
    severity: low
  - summary: >-
      The `PROXIABLE` configure error and the epic's F-10 both attribute the
      P-on-answer rule to RFC 6733 section 3, which does not contain it.
    evidence: |-
      Section 3 says E MUST NOT be set in requests and T MUST NOT be set in
      answers; section 6.2 says an answer's P "is set to the same value as the
      one in the request". The epic's CAP-5 and F-10 nevertheless require P to
      be cleared, so the behaviour is what the contract asks for and this story
      keeps it; only the diagnostic's parenthetical still carries F-10's
      mis-citation, because the story's matrix pins that exact message text and
      correcting it needs an intent-contract amendment this workflow may not
      make. The README states the rule and the deviation without the false
      citation.
    location: >-
      src/diameterencap.cc:40
    severity: low
baseline_revision: '94be58a70d7521747e431350b85215c6a9762db3'
---

<intent-contract>

## Intent

**Problem:** Two paths still emit flag combinations RFC 6733 §3 forbids. `DiameterFlipRequest` toggles R and leaves P as it found it, so a proxiable request becomes an answer that still says it may be proxied (F-10), and `DiameterEncap` accepts any pair of `REQUEST` and `ERROR`/`PROXIABLE`, so a caller can build a request with E set or an answer with P set (CAP-5). Flag initialization landed in story 2, so F-5's `e0` byte on generated requests is already gone; what remains is that no element checks which flags a message type may carry.

**Approach:** `DiameterFlipRequest` clears P whenever it produces an answer. `DiameterEncap` rejects `ERROR` on a request and `PROXIABLE` on an answer at configure time with an error naming the argument and the rule, instead of silently discarding an argument the caller wrote or forwarding a message that is invalid by construction. `DiameterRatedSource` is asserted, not changed.

## Boundaries & Constraints

**Always:** A request never carries E; an answer never carries P; flipping a request clears R and P; a flipped answer sets R and leaves P untouched; flags, Length and identifiers otherwise move byte for byte as today; tabs, zero warnings at `-Wall -Wextra`; element names, argument names, port counts and every existing `.click` config keep working (none passes `ERROR` or `PROXIABLE`).

**Never:** No rule for the T bit (the intent names E and P only); no change to the flag bit layout; no new argument, element or port; no argument renamed or removed; no `srand`/`rand` work (story 6); no man-page or `AC_INIT` work (stories 7, 8). Do not edit `SPEC.md` or `findings.md`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| FLIP_REQUEST_P | `01 00 00 14 c0 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02` through `DiameterFlipRequest` | 20 octets: `01000014 00000118 00000000 00000001 00000002` — R and P cleared | No error expected |
| FLIP_REQUEST_R | Same header with flags `80` | 20 octets: `01000014 00000118 ...` — the existing `flip-request` bytes | No error expected |
| FLIP_ANSWER | Same header with flags `00` | 20 octets: `01000014 80000118 00000000 00000001 00000002` — R set, P stays 0 | No error expected |
| FLIP_ANSWER_P | Same header with flags `40` (P set, invalid input) | 20 octets: `01000014 c0000118 ...` — R set, P untouched: the P rule applies to answers this element produces | No error expected |
| RATED_REQUEST | `DiameterRatedSource(CODE 280, REQUEST true, APPID 42, LIMIT 1, STOP true)` | 20 octets, flags `80`: E=0 | No error expected |
| RATED_ANSWER | same with `REQUEST false` | 20 octets, flags `00`: P=0 | No error expected |
| ENCAP_ERROR_ON_REQUEST | `DiameterEncap(CODE 280, REQUEST true, ERROR true)` | no message configured, no packet | configure fails: `the ERROR argument cannot be set on a request (RFC 6733 section 3)` |
| ENCAP_PROXIABLE_ON_ANSWER | `DiameterEncap(CODE 280, REQUEST false, PROXIABLE true)` | no message configured, no packet | configure fails: `the PROXIABLE argument cannot be set on an answer (RFC 6733 section 3)` |
| ENCAP_ERROR_ON_ANSWER | `DiameterEncap(CODE 280, REQUEST false, ERROR true)` | 24 octets, flags `20` — E is legal on an answer | No error expected |
| ENCAP_RETRANSMIT_ON_REQUEST | `DiameterEncap(CODE 280, REQUEST true, RETRANSMITED true)` | 24 octets, flags `90` — T is legal on a request and unchecked | No error expected |

</intent-contract>

## Code Map

- `src/diameterfliprequest.cc:26-31` -- `put(0)`, `decode`, the `isRequest() ? setRequest(false) : setRequest(true)` toggle, `encode`; the F-10 defect is the toggle leaving `proxiable` alone.
- `src/diameterencap.cc:13-42` -- `configure` parses `CODE`/`REQUEST` (`read_m`), then `ERROR`, `PROXIABLE`, `RETRANSMITED`, `APPID`; the rejection goes after the `Args(...).complete()` guard, before the `dh.set*` block at 34-39. `simple_action` (44-54) only sets hbh, e2e and Length.
- `src/diameter.hh:32-43` -- the constructor that zeroes request/proxiable/error/retransmitted (story 2); `:146-153` -- `encode` writes `request<<7 | proxiable<<6 | error<<5 | retransmitted<<4`, so the flags byte is whatever the three setters hold. Read-only: no layout change.
- `src/diameterratedsource.cc:56-60` -- sets version, Length, request, code and App-Id only; the three flag bits keep the constructor's `false`, which is what F-5's fix already relies on. `:97-98` -- the per-packet `hbh`/`e2e` randoms that tests regex.
- `src/diameterratedsource.hh:18-25` -- the `DiameterHeader dh` member that carries those flags for the element's lifetime.
- `tests/configs/flip-request.click` -- the `80` to `00` config whose bytes must not move; `tests/configs/rated-source.click` -- the flags `80` assertion and its comment about F-5.
- `tests/smoke.bats:31-43` -- `expect` (whole output) and `expect_drop` (exit 0 plus one warning); the configure-failure rows need a third helper. `:209-213` -- the `flip-request` test; `:265-270` -- the `rated-source` test.
- `tests/README.md:65,71,90-95` -- the config table rows and the expectations note; `README.md:154` (the `80` to `00` sentence), `README.md:161-162,167` (the element table), `README.md:208-212` (the F-5/F-10 limitations bullet).
- `_bmad-output/specs/spec-diameter-package-hardening/findings.md:37-42,71-75` -- read-only F-5/F-10 evidence.

## Tasks & Acceptance

**Execution:**
- `src/diameterfliprequest.cc` -- clear `proxiable` in the branch that turns a request into an answer, leaving the answer-to-request branch as it is -- F-10, the only flag defect left in this element.
- `src/diameterencap.cc` -- after parsing, reject `request && error` and `!request && proxiable` with `errh->error` naming the argument and `RFC 6733 section 3` -- CAP-5, without discarding an argument the caller wrote.
- `tests/configs/flip-request-p.click`, `flip-answer.click`, `flip-answer-p.click`, `rated-source-answer.click`, `encap-error-on-answer.click`, `encap-retransmit-on-request.click` -- one config per accepted matrix row, each with its own `Print` label -- the byte assertions.
- `tests/configs/encap-error-on-request.click`, `encap-proxiable-on-answer.click` -- the two rejected rows.
- `tests/smoke.bats` -- add a test per new config, plus an `expect_configure_failure` helper (non-zero exit, message substring, no `Print` line) for the rejected pair -- a regression that accepts the pair fails the run; keep the `flip-request` and `rated-source` tests unchanged.
- `tests/README.md`, `README.md` -- add the config rows, replace the F-5/F-10 limitations bullet with the enforced rule, and state each element's flag contract in the table -- the docs describe the tree as it now behaves.

**Acceptance Criteria:**
- Given a 20-octet request with flags `c0`, when `DiameterFlipRequest` runs, then the flags byte is `00` and the other 19 octets are unchanged (CAP-5, F-10).
- Given a request with flags `80` and an answer with flags `00`, when each flips, then the flags bytes are `00` and `80` — today's bytes, no movement.
- Given an answer with flags `40`, when it flips, then the flags byte is `c0`, because no clause of the intent forces P off on a request this element produces.
- Given `DiameterRatedSource` with `REQUEST true` and again with `REQUEST false`, when each emits, then the flags bytes are `80` and `00` — E is 0 on a request (F-5) and P is 0 on an answer.
- Given `DiameterEncap` with `REQUEST true, ERROR true` or `REQUEST false, PROXIABLE true`, when the router configures, then configuration fails with a message naming the argument and RFC 6733 section 3, and no packet is emitted.
- Given `DiameterEncap` with `REQUEST false, ERROR true` or `REQUEST true, RETRANSMITED true`, when it runs, then the flags bytes are `20` and `90` — E on an answer and T on a request stay legal and unchecked.
- Given the package on Click master, when built at `-Wall -Wextra` and `bats --tap tests` runs, then zero warnings and every test passes, including the unchanged `flip-request`, `rated-source` and `encap*` expectations.

## Spec Change Log

## Review Triage Log

### 2026-11-16 — Review pass
- verdicts: 30 findings — high 0, medium 7, low 18, false 5, maybe-false 0
- findings:
  - `[medium]` `[patch]` the new source comments and docs say RFC 6733 §3 forbids P on an answer — real: §3 says E MUST NOT be set in requests and T MUST NOT be set in answers, while §6.2 sets an answer's P from the request's; the clear-P behaviour stays because CAP-5 and F-10 mandate it, and the comment, the README policy paragraph and the tests prose now attribute to §3 only what it says.
  - `[medium]` `[defer]` `DiameterEncap(REQUEST false, RETRANSMITED true)` configures and emits an answer with T set — real, pre-existing: the T bit has never been checked and the intent names E and P only; recorded in `deferred`.
  - `[low]` `[defer]` flipping an error answer (`20`) yields a request with E set — real, pre-existing: the answer-to-request branch has always kept E, and the intent's E clause covers generated requests; recorded in `deferred`.
  - `[low]` `[patch]` no config sets `PROXIABLE true` with `REQUEST true`, so an over-broad guard ships green — real; `encap-proxiable-on-request.click` and a flags-`c0` test now pin the accept side.
  - `[low]` `[patch]` `sprint-status.yaml` says `ready-for-dev` while the story file says `in-review` — real; set to `review` and `last_updated` refreshed.
  - `[false]` `[reject]` "`review_loop_iteration: 0` on the fourth review pass" — refuted: this is story 5's first pass in its own spec file, so a 0 counter and an empty triage log were correct until this entry.
  - `[false]` `[reject]` the artifact records no results, deferrals or change log — refuted: `## Auto Run Result` is written at finalization and `deferred` is filled by this triage, the same convention as stories 2-4.
  - `[low]` `[patch]` `expect_configure_failure` accepts any non-zero exit whose output merely contains the message — real; the helper now pins Click's three-line configure failure, so a crash, a second error or an extra warning fails the run.
  - `[low]` `[patch]` `tests/README.md` describes the rejected configs twice, never names the new helper, its `encap-*-on-*` glob also matches two accepted configs, and the opening sentence no longer covers configs that print nothing — real; all four are corrected.
  - `[low]` `[patch]` the README flip example flips `80`, so the new sentence about clearing P demonstrates nothing, and `DiameterRatedSource`'s flags are described two ways — real; the example starts from `c0` and the two descriptions agree.
  - `[medium]` `[patch]` deleting the whole "Known limitations" section dropped the pointer to `findings.md` and the record that F-11 and the packaging findings remain, so the README now reads as fully clean — real; a short section naming F-11 and pointing at `findings.md` is restored.
  - `[low]` `[patch]` two test names say the flip sets an "answer bit" — real; renamed to say R is set and the input becomes a request.
  - `[low]` `[reject]` the Code Map line numbers moved with this patch — real drift, but its only fix edits this build's spec.
  - `[low]` `[reject]` verification is not reproducible from the story prose — its fix edits this build's spec too; the commands and their outcomes are recorded in `## Auto Run Result`.
  - `[low]` `[defer]` (edge) a request carrying T flipped to an answer keeps T — real, pre-existing, the same family as the Encap T row; deferred with it.
  - `[medium]` `[defer]` (edge) the answer side of `DiameterEncap` accepts T — same defect and route as the Encap T-bit row.
  - `[low]` `[defer]` (edge) the answer-to-request flip keeps E — same defect and route as the flipped-E row.
  - `[low]` `[patch]` (edge) the sprint record disagrees with the story — same row as the tracker patch.
  - `[medium]` `[patch]` (edge) the "Known limitations" deletion removed the pointer to the open findings — same row as the limitations patch.
  - `[medium]` `[patch]` (edge) the P-on-answer rule contradicts §6.2's mirroring rule — same row as the citation patch; §6.2 is named where the deviation is stated.
  - `[low]` `[patch]` (verification gap) `PROXIABLE true` on a request, the one legal use of P, is never exercised — same row as the proxy accept-side patch.
  - `[low]` `[patch]` (verification gap) the `encap-*-on-*` glob matches four configs, two of them accepted — same row as the tests/README patch.
  - `[low]` `[patch]` (verification gap) the tracker and the story disagree about the story's state — same row as the tracker patch.
  - `[false]` `[reject]` E=0 is asserted on an answer rather than on a request — refuted: the unchanged `rated-source` test pins flags `80` on a generated request and passed in this run; the new answer config adds the P side, it does not replace the E side.
  - `[low]` `[patch]` Encap's P is only exercised at the configure surface, never on the wire — real overlap with the accept-side row; the new proxy config puts flags `c0` on the wire.
  - `[low]` `[defer]` the answer-to-request branch can emit E, which the story's "Always" clause forbids — same defect and route as the flipped-E row.
  - `[false]` `[reject]` the tests pin English prose the intent never specifies — refuted: the story's matrix fixes the message verbatim, so pinning it is this run's contract, and every `malformed-*` test pins its warning the same way.
  - `[low]` `[patch]` the queue and the tracker disagree, so "next queued story" still resolves to story 5 — same row as the tracker patch; finalization also commits the work.
  - `[false]` `[reject]` the change carries no run evidence and Click cannot run on this host — refuted: the suite ran twice in WSL, 52/52 on the plain prefix and 52/52 under AddressSanitizer, and `## Auto Run Result` records it.
  - `[medium]` `[patch]` the documentation narrows CAP-5 to the construction side and drops the recorded defect set — same row as the limitations patch.

## Design Notes

- **Rejection, not normalization, for `DiameterEncap`.** The element's flags are a caller's declaration, and both live records of the gap frame it as an unchecked caller input: CAP-5 says the elements must "set them consistently with the message type", and `README.md:211-212` (written when story 2 closed F-5's initialization) says "nothing checks what a caller then sets". Silently overriding `ERROR true` would repair a wrong configuration into a plausible-looking message, which the epic's malformed-input constraint forbids for packets; a named configure error leaves the caller's argument intact and fails loudly.
- **FlipRequest normalizes where Encap rejects.** `DiameterFlipRequest` has no argument surface — it is handed a packet and must emit one — so it cannot refuse; clearing P is the only way to keep the answer it produces conforming. The two policies therefore differ by what each element owns, not by taste.
- **P is cleared only on the answer side.** The intent scopes the rule to "converts a request to an answer", and the epic constrains a fix to change behaviour only where it must. An answer legally has P=0, so a flipped answer is a non-proxiable request today and stays one; an illegally-proxied answer keeps its bit rather than gaining a second rule.
- **F-5 needs an assertion, not an edit.** `DiameterRatedSource` never assigns `proxiable`, `error` or `retransmitted`; story 2's constructor initializes them to `false`, so generated requests already show `80`, not F-5's `e0`. The story pins that with an answer config as well, so a future constructor change cannot silently reintroduce E on a request.
- **Pre-fix probes** (2026-11-16, `$HOME/click-master` prefix, this baseline): a `c0` request through `DiameterFlipRequest` prints flags `40` — P survives the flip, which is F-10; an answer with flags `40` prints `c0` and must keep doing so; and `DiameterEncap(CODE 280, REQUEST true, ERROR true)` configures happily and emits flags `a0`.

## Verification

**Commands:**
- Export the working tree to WSL with LF endings; `autoconf && ./configure --with-click=$HOME/click-master --prefix=$HOME/click-master && make && make install` -- expected: zero warnings, `diameter.uo` installed.
- `g++ -fsyntax-only -W -Wall -Wextra src/*.cc` with the package's include flags -- expected: no output.
- `CLICK=$HOME/click-master/bin/click bats --tap tests` -- expected: every test passes, including the new configs and the unchanged flag expectations.
- Install into the AddressSanitizer prefix and run the full suite -- expected: exit 0, no sanitizer report.

**Manual checks (if no CLI):**
- Run `flip-request-p.click` and read flags `00`; run `flip-answer-p.click` and read `c0`; run `encap-error-on-request.click` and confirm a non-zero exit with the named error and no `Print` line.
