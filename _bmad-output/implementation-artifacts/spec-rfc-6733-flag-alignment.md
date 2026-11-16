---
title: 'Align the Diameter flags with RFC 6733'
type: 'bugfix'
created: '2026-11-16'
status: 'done'
review_loop_iteration: 0
followup_review_recommended: false
context: ['{project-root}/AGENTS.md']
warnings: []
deferred:
  - summary: >-
      `diameter_check_header` still does not validate the version octet, so a
      frame carrying version `0x2a` passes every reader.
    evidence: |-
      The guard checks the 20-octet minimum, the declared Length and now the
      flags, but never `buffer[0]`. Pre-existing: F-4 covers generated frames,
      which the `DiameterHeader` constructor keeps at version 1, and neither the
      intent nor any finding asks the readers to police the version. Adding a
      reason is a one-line change plus a config, but it is a new drop class the
      user's three answers do not name.
    location: >-
      src/diameter.hh:318
    severity: low
baseline_revision: 'a98dea68ec5dca1937dbb2af7a0eb641de4d3ad6'
---

<intent-contract>

## Intent

**Problem:** The flag policy is not the RFC's. Story 5 cleared P whenever `DiameterFlipRequest` produced an answer and made `DiameterEncap` reject `PROXIABLE` on an answer, but RFC 6733 §6.2 sets an answer's P "to the same value as the one in the request", so a proxiable request must stay proxiable when it becomes an answer. In the other direction the two rules the RFC does state are unenforced: §3 (and §7.2) says E "MUST NOT be set in request messages" and T "MUST NOT be set in answer messages", yet a flip carries E into a request and T into an answer, `DiameterEncap` accepts `RETRANSMITED true` on an answer, and no element rejects a received frame that violates either rule. User direction of 2026-11-16 fixed the reading: P mirrors, E and T are policed, on both the construction and the receive side.

**Approach:** Move the rules where the RFC puts them. `DiameterFlipRequest` keeps P and clears T when it produces an answer, and keeps P and clears E when it produces a request. `DiameterEncap` rejects `ERROR` on a request and `RETRANSMITED` on an answer and accepts `PROXIABLE` on either. The shared header guard gains both flag reasons, so every element that reads a message drops E-on-request and T-on-answer through the existing one-line warning.

## Boundaries & Constraints

**Always:** A constructed request never carries E; a constructed answer never carries T; a flip preserves P in both directions; a received message carrying E on a request or T on an answer is dropped with one `ELEMENT: dropping malformed packet: REASON` line, not throttled; the Length and AVP reasons keep their order and text, so the flag reasons are reached only by a frame whose Length is already right; P on either type, E on an answer and T on a request stay legal; tabs, zero warnings at `-Wall -Wextra`; element names, arguments, port counts and every other `.click` config keep working.

**Never:** No new argument, element or port; no flag bit-layout change; no rule for the AVP header's V and M bits; no `srand`/`rand` work (story 6); no man-page or `AC_INIT` work (stories 7, 8); no change to what the Length and AVP guards accept. Do not rewrite story 5's review record — append to it.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| FLIP_REQUEST_P | `01 00 00 14 c0 00 01 18 ...` (R,P) through `DiameterFlipRequest` | 20 octets: `01000014 40000118 ...` — R cleared, P mirrored | No error expected |
| FLIP_REQUEST_T | flags `90` (R,T) | flags `00` — T cleared with R | No error expected |
| FLIP_REQUEST_PT | flags `d0` (R,P,T) | flags `40` — P mirrored, T cleared | No error expected |
| FLIP_REQUEST_R | flags `80` (R) | flags `00` — the existing `flip-request` bytes | No error expected |
| FLIP_ANSWER | flags `00` | flags `80` — R set, P stays 0 | No error expected |
| FLIP_ANSWER_E | flags `20` (E) | flags `80` — E cleared, a request may not carry it | No error expected |
| FLIP_ANSWER_P | flags `40` (P) | flags `c0` — R set, P mirrored | No error expected |
| FLIP_ANSWER_EP | flags `60` (P,E) | flags `c0` — P kept, E cleared | No error expected |
| ENCAP_ERROR_ON_REQUEST | `DiameterEncap(CODE 280, REQUEST true, ERROR true)` | no packet | configure fails: `the ERROR argument cannot be set on a request (RFC 6733 section 3)` |
| ENCAP_RETRANSMIT_ON_ANSWER | `REQUEST false, RETRANSMITED true` | no packet | configure fails: `the RETRANSMITED argument cannot be set on an answer (RFC 6733 section 3)` |
| ENCAP_PROXIABLE_ON_ANSWER | `REQUEST false, PROXIABLE true` | 24 octets, flags `40` — the P of the request it answers | No error expected |
| ENCAP_PROXIABLE_ON_REQUEST | `REQUEST true, PROXIABLE true` | 24 octets, flags `c0` | No error expected |
| ENCAP_ERROR_ON_ANSWER | `REQUEST false, ERROR true` | 24 octets, flags `20` | No error expected |
| ENCAP_RETRANSMIT_ON_REQUEST | `REQUEST true, RETRANSMITED true` | 24 octets, flags `90` | No error expected |
| DROP_E_ON_REQUEST | 24-octet message flags `a0` (R,E) through `DiameterDecap` | no packet forwarded | `DiameterDecap: dropping malformed packet: the E bit is set on a request` |
| DROP_E_ON_REQUEST_MESSAGE | same frame through `DiameterPopAVP` | no packet forwarded | `DiameterPopAVP: dropping malformed packet: the E bit is set on a request` |
| DROP_T_ON_ANSWER | 20-octet answer flags `10` (T) through `DiameterFlipRequest` | no packet forwarded | `DiameterFlipRequest: dropping malformed packet: the T bit is set on an answer` |

</intent-contract>

## Code Map

- `src/diameter.hh:278-307` -- the `DiameterCheck` enum and `diameter_check_reason`; the two flag reasons are appended here, so no existing value moves. `:311-320` -- `diameter_check_header`, the single place all message readers share: Length first, then the flag test on `buffer[4]` (`0x20` is E, `0x10` is T, `0x80` is R). `:355-381` -- `diameter_check_message` calls it first, so PopAVP, PushAVP and PopStorePushAVP inherit the rule.
- `src/diameterfliprequest.cc:26-40` -- the decode/toggle/encode; each branch now touches P not at all, clears T on the answer branch and clears E on the request branch.
- `src/diameterencap.cc:35-42` -- the two guards added by story 5; the `PROXIABLE` guard goes, a `RETRANSMITED` guard takes its place, and the ERROR message text stays byte-identical.
- `src/diameterratedsource.cc:56-60` -- sets no flag bit beyond R, so both message types conform; unchanged, asserted by its two configs.
- `tests/configs/flip-request-p.click` -- expects `c0` to `00` today; becomes `c0` to `40`. `flip-answer-p.click` (`40` to `c0`) and `flip-answer.click` (`00` to `80`) keep their bytes. `encap-proxiable-on-answer.click` is a rejection config today and becomes an accept config with flags `40`; `encap-retransmit-on-answer.click` takes its place as the rejection.
- `tests/smoke.bats:47-56` -- `expect_configure_failure CONFIG MESSAGE` pins Click's whole configure failure for the `DiameterEncap@2` element; the accept configs use the existing `expect` and the drop configs `expect_drop` (`:38-45`).
- `tests/README.md:26-40,45-105` -- the run notes, the config table and the expectations paragraph; `README.md` "Flag policy" and "Known limitations" sections plus the `DiameterFlipRequest`/`DiameterEncap` rows of the element table.
- `_bmad-output/specs/spec-diameter-package-hardening/SPEC.md:29-31` (CAP-5), `findings.md:37-42` (F-5) and `:71-75` (F-10), `stories.yaml:53-66` (the story-5 entry), `planning-artifacts/epics.md:27-29`, `.memlog.md` -- the contract this change amends, on the user's direction of 2026-11-16.

## Tasks & Acceptance

**Execution:**
- `src/diameter.hh` -- add `DIAMETER_CHECK_ERROR_ON_REQUEST` and `DIAMETER_CHECK_RETRANSMITTED_ON_ANSWER` with their reason strings, and test the flags byte in `diameter_check_header` after the Length check -- one guard, every message reader.
- `src/diameterfliprequest.cc` -- stop clearing P; clear T on the request-to-answer branch and E on the answer-to-request branch -- the RFC's two prohibitions and its mirroring rule.
- `src/diameterencap.cc` -- replace the `PROXIABLE`-on-answer guard with a `RETRANSMITED`-on-answer guard and leave the ERROR guard and its message alone -- the same pair rule, with the RFC's bits.
- `tests/configs/` -- `flip-request-p`, `flip-request-t`, `flip-request-pt`, `flip-answer-e`, `flip-answer-ep` (new or moved), `encap-proxiable-on-answer` (now accepted), `encap-retransmit-on-answer` (now rejected), `malformed-error-on-request`, `malformed-error-on-request-message`, `malformed-retransmit-on-answer` -- one config per matrix row, each with its own `Print` label or drop warning.
- `tests/smoke.bats` -- a test per new or moved config, moving `flip-request-p`'s expectation to `40`, turning `encap-proxiable-on-answer` into an accept test and adding the `encap-retransmit-on-answer` rejection; keep every other flag expectation unchanged.
- `tests/README.md`, `README.md` -- the config rows, the drop reasons, the flag policy stated as the RFC's (P mirrors, E not in requests, T not in answers, received frames validated), and the element rows for `DiameterFlipRequest` and `DiameterEncap`.
- `_bmad-output/specs/spec-diameter-package-hardening/SPEC.md`, `findings.md`, `stories.yaml`, `planning-artifacts/epics.md`, `.memlog.md` -- update CAP-5, F-10, the story-5 entry, the epics index line and the decision log to the rule this change enforces -- the contract has to describe the tree.
- `_bmad-output/specs/spec-diameter-package-hardening/stories/5-set-request-and-answer-flags-per-rfc-6733.md` -- append a `## Spec Change Log` entry recording that its P rule was superseded by user direction, with a pointer to this spec -- history stays append-only.

**Acceptance Criteria:**
- Given a request with flags `c0`, `90` or `d0`, when `DiameterFlipRequest` runs, then the answer's flags byte is `40`, `00` or `40` — P mirrored, T cleared (CAP-5).
- Given an answer with flags `20`, `40` or `60`, when it flips, then the flags byte is `80`, `c0` or `c0` — E cleared, P mirrored.
- Given `DiameterEncap` with `REQUEST false, PROXIABLE true`, when it runs, then the packet is 24 octets with flags `40`; with `REQUEST true, ERROR true` or `REQUEST false, RETRANSMITED true`, configuration fails naming the argument and RFC 6733 section 3.
- Given a frame carrying E on a request or T on an answer, when `DiameterDecap`, `DiameterFlipRequest`, `DiameterPopAVP`, `DiameterPushAVP` or `DiameterPopStorePushAVP` reads it, then it drops the frame with one warning naming the element and the flag reason.
- Given a frame carrying P on either type, E on an answer or T on a request, when any of those elements reads it, then it forwards it unchanged — the rules are pairs, not bans.
- Given the package on Click master, when built at `-Wall -Wextra` and `bats --tap tests` runs, then zero warnings and every test passes, including every unchanged expectation.

## Spec Change Log

## Review Triage Log

### 2026-11-16 — Review pass
- verdicts: 28 findings — high 0, medium 2, low 25, false 1, maybe-false 0
- findings:
  - `[low]` `[patch]` the README's six-reader sentence says all six validate "length, flags and AVP framing", but `DiameterAvpDecap` reads an AVP and never sees a message header — real; the sentence now splits the five message readers from the AVP reader.
  - `[low]` `[patch]` "P on either type, E on an answer and T on a request pass through unchanged" is falsified by the flip, which rewrites E and T — real; the claim now covers the readers that only validate and says what the flip does.
  - `[low]` `[patch]` the new asymmetry is unexplained: a T-bearing answer is dropped by the flip although flipping it would produce a legal request — real; the flag policy now states the validate-at-the-door rule and names the case.
  - `[low]` `[patch]` the `rated-source-answer` row says "E and P clear" while CAP-5 now succeeds on T=0 — real; the row reads "E, P and T clear".
  - `[low]` `[patch]` the `encap-proxiable-on-answer` row says "mirroring the request" while the policy says Encap has no request to mirror, and `flip-answer-p` cites §6.2 for a direction §6.2 does not govern — real; both now state the caller's declaration and the package decision.
  - `[medium]` `[patch]` no config feeds a legal flag combination to a reader, so an over-dropping guard ships green — real; `decap-p-on-answer`, `decap-t-on-request` and `pop-avp-error-on-answer` now pin the forwarding half.
  - `[low]` `[patch]` the acceptance criterion names `DiameterPushAVP` and `DiameterPopStorePushAVP` while no config exercises a drop through either — real; `malformed-error-on-request-push` and `malformed-retransmit-on-answer-popstorepush` close it.
  - `[low]` `[defer]` the version octet is still unvalidated while the hunk is described as validating the header — real and pre-existing; the intent names flags only, so it is recorded in `deferred`.
  - `[low]` `[patch]` "T on a request is legal" is stated flatly; §3 conditions it on a retransmission — real; the docs and the `flip-request-t` comment now say it is not checked, and why.
  - `[low]` `[patch]` F-10's Where line still lists only `src/diameterfliprequest.cc` although the entry now covers Encap and the guard — real; the line names all three files.
  - `[low]` `[patch]` F-10's heading uses a real em dash among double-encoded neighbours, it carries a Resolution bullet that F-5 lacks, and the pre-fix evidence was replaced rather than kept — real; the heading is ASCII, the observed bytes are kept in the Symptom, and F-5 gains the matching Resolution line.
  - `[low]` `[reject]` every Code Map line reference is pre-change numbering — real drift, but its only fix edits this build's spec.
  - `[low]` `[reject]` the new spec's frontmatter keys differ from the sibling CI spec's — its fix also edits this build's spec; `review_loop_iteration: 0` and `followup_review_recommended: false` are correct until this entry writes them.
  - `[low]` `[patch]` `malformed-retransmit-on-answer` labels its Print with the config name where every other `malformed-*` labels the element — real, though the line never prints; renamed `flip-request`.
  - `[low]` `[patch]` the four reading elements' rows still describe only their operation — real; each now says it validates the message first.
  - `[low]` `[patch]` the story-5 change-log entry says "the review record above" while that record sits below it — real; reworded to name the file's record without a direction.
  - `[low]` `[patch]` (edge) the README six-reader claim — same row as the scope patch.
  - `[low]` `[patch]` (edge) a smoke-test comment still cites "the accept side of the P guard" this change deleted — real; the comment now says a guard that rejected PROXIABLE at all fails there.
  - `[low]` `[patch]` (verification gap) the Length-before-flags order is unpinned, so hoisting the flag test would stay green — real; `malformed-error-on-request-length` carries both faults and pins the Length reason.
  - `[medium]` `[patch]` the no-false-drop half is asserted only in prose — same row as the legal-forward patch; the new configs put P, E and T through real readers.
  - `[low]` `[patch]` (intent) the README's "on the receive side" overstates what a receiver can check — same row as the pass-through patch.
  - `[low]` `[patch]` (intent) reader coverage is 5 in the acceptance and 3 in the tests — same row as the two-reader patch.
  - `[low]` `[patch]` (intent) the documented scope is six readers while the code is five — same row as the scope patch.
  - `[low]` `[patch]` (intent) the Length-versus-flag precedence is a diff-side decision no test pins — same row as the precedence patch.
  - `[low]` `[patch]` (intent) the flip refuses an input it could normalise — same row as the asymmetry patch.
  - `[false]` `[reject]` the tests bind two behaviours clause (1) does not mention (P kept on the answer-to-request flip, `RETRANSMITED` rejected on an answer) — refuted: the intent is "align the flags with what the RFC defines", and §3 forbids E in a request and T in an answer, so clearing E on a flip that produces a request and refusing a constructed T-bearing answer are the rule itself, not an extension.
  - `[low]` `[patch]` (intent) F-10's evidence was rewritten instead of updated, and its heading mixes encodings — same row as the F-10 patch.

## Design Notes

- **One guard, not six.** Every message reader already funnels through `diameter_check_header` (directly in Decap and FlipRequest, through `diameter_check_message` in PushAVP, PopAVP and PopStorePushAVP), so the flag test belongs there. It runs after the Length check so an existing malformed-length test keeps reporting the length reason rather than gaining a second one, and it takes the flags byte as-is — no element ever parses flags into a `DiameterHeader` before validating.
- **P is preserved, not computed.** §6.2's mirroring rule is a property of an answer generated from a request; a stateless flip can only preserve the bit it received, and that is what "set to the same value as the one in the request" asks of it. `DiameterEncap` has no request to mirror, so it accepts the caller's declaration on either type, which is why the old `PROXIABLE`-on-answer rejection goes.
- **The two reasons read as sentences, not flags.** `the E bit is set on a request` and `the T bit is set on an answer` follow the existing `click_chatter` shape (`ELEMENT: dropping malformed packet: REASON`), so the drop tests reuse `expect_drop` without a new helper.
- **Pre-fix probes** (2026-11-16, `$HOME/click-master` prefix, this baseline): a `90` request through `DiameterFlipRequest` prints flags `10` today (T survives into an answer), a `20` answer prints `a0` (E survives into a request), `DiameterEncap(CODE 280, REQUEST false, RETRANSMITED true)` emits flags `10`, and a `a0` request reaches `DiameterDecap`, which forwards it after stripping the header.

## Verification

**Commands:**
- Export the working tree to WSL with LF endings; `autoconf && ./configure --with-click=$HOME/click-master --prefix=$HOME/click-master && make && make install` -- expected: zero warnings, `diameter.uo` installed.
- `g++ -fsyntax-only -I$HOME/click-master/include -W -Wall -Wextra src/*.cc` -- expected: no output.
- `CLICK=$HOME/click-master/bin/click bats --tap tests` -- expected: every test passes, including the moved and new flag expectations.
- Install into the AddressSanitizer prefix and run the full suite -- expected: exit 0, no sanitizer report.

**Manual checks (if no CLI):**
- Run `flip-request-t.click` and read flags `00`; `flip-answer-e.click` and read `80`; `encap-proxiable-on-answer.click` and read `40`; `malformed-error-on-request.click` and confirm the drop warning and no `Print` line.

## Auto Run Result

Summary: The flag policy is now the RFC's, on both sides of the wire. `DiameterFlipRequest` keeps P in both directions, clears T when it produces an answer and clears E when it produces a request; `DiameterEncap` rejects `ERROR` on a request and `RETRANSMITED` on an answer and accepts `PROXIABLE` on either, because §6.2 mirrors a request's P and Encap has no request to consult; and `diameter_check_header` gained the two flag reasons, so every element that reads a message drops a frame carrying E on a request or T on an answer with the existing one-line warning, after the Length check so a doubly malformed frame still reports the Length. Story 5's stricter P rule — clear P on answers, reject `PROXIABLE` on an answer — is reversed, and the epic contract now records the RFC's rule instead of the package's. Seventeen matrix rows are pinned by configs and tests, including the positive half (P on either type, E on an answer and T on a request are forwarded) and the Length-before-flags precedence.

Files changed:
- `src/diameter.hh` — two `DiameterCheck` values and their reason strings; the flag test in `diameter_check_header` behind the Length comparison.
- `src/diameterfliprequest.cc` — P untouched in both branches; T cleared on the answer branch, E on the request branch.
- `src/diameterencap.cc` — the `PROXIABLE`-on-answer guard replaced by `RETRANSMITED`-on-answer; the ERROR message unchanged.
- `tests/configs/` — `flip-request-t`, `flip-request-pt`, `flip-answer-e`, `flip-answer-ep`, `encap-retransmit-on-answer`, `decap-p-on-answer`, `decap-t-on-request`, `pop-avp-error-on-answer`, `malformed-error-on-request`, `malformed-error-on-request-message`, `malformed-error-on-request-push`, `malformed-error-on-request-length`, `malformed-retransmit-on-answer`, `malformed-retransmit-on-answer-popstorepush`; `flip-request-p` moved to `40`, `encap-proxiable-on-answer` became an accept config.
- `tests/smoke.bats` — fourteen new tests (53 → 67), one expectation moved, one rejection replaced, one accept test added, and the stale comment that cited the deleted P guard corrected.
- `tests/README.md`, `README.md` — the config rows, the drop reasons and precedence, the flag policy stated as the RFC's with the flip's validate-at-the-door consequence, the reader rows, and the six-reader split between message and AVP validation.
- `_bmad-output/specs/spec-diameter-package-hardening/SPEC.md`, `findings.md`, `stories.yaml`, `planning-artifacts/epics.md`, `.memlog.md` — CAP-5 intent and success, F-10's scope, symptom and resolution, F-5's resolution line, the story-5 entry, the epic index line, and the decision log.
- `_bmad-output/specs/spec-diameter-package-hardening/stories/5-set-request-and-answer-flags-per-rfc-6733.md` — an append-only Spec Change Log entry recording the supersession.
- `_bmad-output/implementation-artifacts/spec-rfc-6733-flag-alignment.md` — this spec.

Review findings breakdown: 28 findings — high 0, medium 2, low 25, false 1, maybe-false 0. Patched: 14 entries — 1 medium and 13 low: the receive rule's positive half and the two unexercised readers are now configs and tests (six added), the Length-before-flags precedence is pinned, the README's six-reader and pass-through claims are corrected, the flip's new drop is explained, F-10's Where line, encoding, kept evidence and F-5's resolution are fixed, the reader table rows say they validate, and four stale wordings (rated-source answer row, proxiable row and comment, "T is legal on a request", the deleted P guard comment, the story-5 "above") are corrected. Deferred: 1 — the version octet is still unvalidated, which predates this change and is outside the intent's flag rules. Rejected: 1 false — that the tests bind two behaviours the intent does not name; §3 forbids E in a request and T in an answer, so clearing E on a flip that produces a request and refusing a constructed T-bearing answer are the rule the intent names. Rejected: 2 low — the Code Map's pre-change line numbers and the new spec's frontmatter keys, whose only fixes edit this build's spec.

Follow-up review recommendation: false. One medium entry was patched on a first pass, and the rule needs a patched high or two medium entries; the receive path's positive and negative halves, the Length precedence and both unexercised readers are now covered by configs that ran.

Verification performed (WSL Ubuntu 26.04, GCC 15.2, Click 2.1 built from upstream master `9197a594b`):
- Fresh LF export of the final tree: `autoconf && ./configure --with-click=$HOME/click-master --prefix=$HOME/click-master && make && make install` — zero compiler warnings, `diameter.uo` installed.
- `g++ -fsyntax-only -I$HOME/click-master/include -W -Wall -Wextra src/*.cc` — no output, exit 0.
- `CLICK=$HOME/click-master/bin/click bats --tap tests` — 67/67 pass, exit 0, including the seven flip configs, eight encap configs, six new receive rows and every unchanged expectation.
- AddressSanitizer: rebuilt and installed into `$HOME/click-asan`, full suite under `ASAN_OPTIONS=detect_leaks=1` — 67/67 pass, exit 0, no sanitizer report.
- Manual bytes: `flip-request-t` prints `01000014 00000118 ...` (flags `00`), `flip-answer-e` `80000118`, `encap-proxiable-on-answer` `40000118`, `decap-p-on-answer` and `decap-t-on-request` forward `deadbeef`, `pop-avp-error-on-answer` prints the 20-octet header unchanged; the four drop configs each print exactly one warning with no `Print` line, and `malformed-error-on-request-length` reports `header Length does not match packet length`.
- Matrix audit: every row has a test that ran and passed — FLIP_REQUEST_P (22), FLIP_REQUEST_T (23), FLIP_REQUEST_PT (24), FLIP_REQUEST_R (21), FLIP_ANSWER (25), FLIP_ANSWER_E (27), FLIP_ANSWER_P (26), FLIP_ANSWER_EP (28), ENCAP_ERROR_ON_REQUEST (40), ENCAP_RETRANSMIT_ON_ANSWER (42), ENCAP_PROXIABLE_ON_ANSWER (41), ENCAP_PROXIABLE_ON_REQUEST (39), ENCAP_ERROR_ON_ANSWER (37), ENCAP_RETRANSMIT_ON_REQUEST (38), DROP_E_ON_REQUEST (61), DROP_E_ON_REQUEST_MESSAGE (62), DROP_T_ON_ANSWER (63).

Residual risks: `linuxmodule` and `bsdpkg` cannot be built on this host, so their compilability rests on the change staying in a shared header and two `.cc` files that already used these APIs. The receive rule now drops frames the package previously forwarded, which is the point, but a graph that fed a non-conforming peer's traffic through this package will lose those packets and log one line per drop. §6.2's mirroring cannot be checked on receipt, so an answer whose P disagrees with a request it never saw still passes. The version octet remains unvalidated (`deferred`). `findings.md` still carries its pre-existing double-encoded em dashes and section signs outside the F-10 and F-5 entries this change touched.
