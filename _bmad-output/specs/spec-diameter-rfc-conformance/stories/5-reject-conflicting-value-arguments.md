---
title: 'Reject conflicting value arguments'
type: 'bugfix'
created: '2026-11-17'
status: 'done'
review_loop_iteration: 0
followup_review_recommended: false
baseline_revision: 'f9a70d0eb5c87d6806d1b64bbcab0d22ac8ab66c'
context: ['{project-root}/AGENTS.md']
warnings: ['oversized']
deferred: []
---

<intent-contract>

## Intent

**Problem:** `DiameterPushAVP` reads its seven value arguments as independent optionals and resolves them by `if`/`else` order, so a configuration that supplies two of them silently emits one and discards the other: `OCTETSTRING "abc", UINT32 7` emits `abc`, and `RANDNUMSTRING 4, RANDHEXSTRING 4` draws the first. The user gets an AVP they did not ask for and no diagnostic, while the discarded argument is exactly the one that decides the encoded value type (finding A-10, CAP-1).

**Approach:** After parsing, decide which value sources are supplied and fail configure when more than one is, naming both arguments in the error the way `DiameterEncap` refuses `ERROR` on a request. Replace the man page's precedence text with the one-source rule.

## Boundaries & Constraints

**Always:** A configuration with exactly one supplied source keeps today's exact bytes and draw order; `OCTETSTRING` counts as supplied when its keyword is present, including `OCTETSTRING ""` (the documented no-value request); `UINT32` counts when present, including `0` (four zero octets since story 4); `RANDUINT32` counts only when true; a `RAND*STRING` generator counts only when its count is above zero, the documented "unused" value; the error names both conflicting arguments; tabs for indentation; the package stays warning-free at `-Wall -Wextra`.

**Never:** No change to a single source's value, the `click_random()` call order, the AVP or message Length, or the data path; no new argument; no duplicate-keyword handling (`OCTETSTRING "a", OCTETSTRING "b"` stays Click's last-wins, deferred by story 3); no change to the `VENDORSPEC`/`VENDOR` or `MANDATORY` rules; no RFC citation in the new error, which is an argument-surface rule rather than an on-the-wire one; no edit to `.github/workflows/`.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| Cross-type conflict | `DiameterPushAVP(CODE 264, OCTETSTRING "abc", UINT32 7)` on the shared 20-octet request | configure fails before any packet | error names `OCTETSTRING` and `UINT32` |
| Generator conflict | `CODE 264, RANDNUMSTRING 4, RANDHEXSTRING 4` | configure fails before any packet | error names `RANDNUMSTRING` and `RANDHEXSTRING` |
| Empty string is still a source | `CODE 268, OCTETSTRING "", UINT32 0` | configure fails: the empty string requests the no-value AVP, the zero is a value | error names `OCTETSTRING` and `UINT32` |
| Zero-count generator is unused | `CODE 264, RANDNUMSTRING 0, RANDHEXSTRING 4` | 32-octet frame, AVP Length 12, four hex characters | No error expected |
| False boolean is unused | `CODE 264, RANDUINT32 false, OCTETSTRING "abc"` | 32 octets, byte-identical to `push-avp.click` | No error expected |
| Single source, unchanged | `push-avp.click`, `push-avp-uint32.click`, `push-avp-rand.click`, `push-avp-empty.click`, `push-avp-no-value.click`, `rand-*`, `randomness-*` | the same bytes or pattern as the pre-change build | No error expected |
| Repeated same keyword | `OCTETSTRING "a", OCTETSTRING "b"` | configures and the last value wins; unchanged Click `Args` behaviour | No error expected |

</intent-contract>

## Code Map

- `src/diameterpushavp.cc:73-128` -- `configure()`; `:79-88` the initialised locals, `uintSpecified` at `:88` is the presence idiom to copy; `:90-102` the `Args` chain, `.read("OCTETSTRING", datastring)` at `:95` gains `.read_status(...)`; `:108` `hasUint`; `:110-113` the existing `VENDORSPEC` refusal, the ordering neighbour; `:148-167` the precedence chain whose single-source behaviour must not move; `:173` the value-length expression.
- `src/diameterpushavp.hh:15` -- the `=c` SYNOPSIS, unchanged (no argument is added).
- `src/diameterpushavp.hh:41-55` -- the `=d` value paragraph; "A non-empty OCTETSTRING wins even over RANDUINT32" is the precedence text this story replaces.
- `src/diameterpushavp.hh:83-100` -- `=item OCTETSTRING`, `=item UINT32`, `=item RANDUINT32`; each describes the if/else precedence and must state the one-source rule instead.
- `src/diameterpushavp.hh:140-152` -- configuration-only members; no new member is needed, so the per-packet-local shape story 1 introduced stays intact.
- `src/diameterencap.cc:39-42` -- the configure-error style to follow: `return errh->error("the ERROR argument cannot be set on a request (RFC 6733 section 3)");`.
- `/tmp/opencode/click-mt/include/click/args.hh:649-661` -- read-only: `read_status(bool &x)` carries the presence of the last `read()`, the idiom story 4 used for `UINT32`.
- `tests/smoke.bats:18-43` -- the header comment that names which push-avp configs pin what and says "the four configs the package refuses"; `:105-116` `expect_configure_failure`; `:155-275` the push-avp byte tests; `:176-187` the two vendor refusals as the failure-test model.
- `tests/configs/push-avp.click`, `push-avp-rand.click`, `rand-hex-one.click`, `push-avp-uint32.click` -- the 20-octet request and the literal/pattern test shapes the new configs copy.
- `tests/README.md:171-181` -- the configure-path paragraph that counts four refused configs; `:194-215` the config table.
- `README.md:142-145` -- the prose that lists the value sources without saying they are exclusive; `:178` the element-reference row, which already says "one of" but not that two are refused.
- `tests/manpages.bats:128-131` -- read-only: the eleven-argument enumeration does not change.

## Tasks & Acceptance

**Execution:**
- `src/diameterpushavp.cc` -- capture `bool octetSpecified = false;` beside `uintSpecified` with `.read("OCTETSTRING", datastring).read_status(octetSpecified)`, and after `Args().complete()` succeeds walk the seven sources in documented order whose supplied predicate is `octetSpecified`, `uintSpecified`, `randUInt32`, `randAlphaNumString > 0`, `randNumString > 0`, `randAlphaString > 0`, `randHexString > 0`; on the second supplied source return `errh->error("the %s and %s arguments cannot be used together: at most one value source may be supplied", first, current)`, placed before `hasUint` and the `VENDORSPEC` refusal -- two sources must never resolve by if/else again.
- `src/diameterpushavp.hh` -- replace the `=d` precedence paragraph with the one-source rule: supplying two fails configuration with an error naming both; state that `OCTETSTRING` and `UINT32` count when present (an empty string and a zero number are values), `RANDUINT32` when true, and a `RAND*STRING` when its count is above zero; correct `=item OCTETSTRING`, `=item UINT32` and `=item RANDUINT32` to say they cannot be combined -- the man page is the only place a caller learns the rule.
- `tests/configs/push-avp-conflict-octetstring-uint32.click` -- `CODE 264, OCTETSTRING "abc", UINT32 7` -- pins the A-10 repro as a configure failure naming both arguments.
- `tests/configs/push-avp-conflict-randnumstring-randhexstring.click` -- `CODE 264, RANDNUMSTRING 4, RANDHEXSTRING 4` -- pins the generator pair that used to take the first silently.
- `tests/configs/push-avp-conflict-empty-octetstring-uint32.click` -- `CODE 268, OCTETSTRING "", UINT32 0` -- pins that an empty string is a supplied source, so the fix cannot be a `length() > 0` test.
- `tests/configs/push-avp-rand-zero.click` -- `CODE 264, RANDNUMSTRING 0, RANDHEXSTRING 4` -- pins that a zero count is the documented "unused", not a conflict, and that the hex source still supplies.
- `tests/configs/push-avp-randuint32-false.click` -- `CODE 264, RANDUINT32 false, OCTETSTRING "abc"` -- pins that a false boolean is not a source; the frame is byte-identical to `push-avp.click`.
- `tests/configs/push-avp-conflict-octetstring-randuint32.click` -- `CODE 264, OCTETSTRING "abc", RANDUINT32 true` -- pins the boolean's true branch of the presence table, so deleting that row fails a test.
- `tests/configs/push-avp-conflict-randalphanumstring-randalphastring.click` -- `CODE 264, RANDALPHANUMSTRING 1, RANDALPHASTRING 1` -- pins the two generator rows the generator-pair config does not exercise.
- `tests/configs/push-avp-conflict-three.click` -- `CODE 264, OCTETSTRING "abc", UINT32 7, RANDHEXSTRING 4` -- pins that a three-source config names the first conflicting pair in argument order.
- `tests/configs/push-avp-duplicate-octetstring.click` -- `CODE 264, OCTETSTRING "a", OCTETSTRING "bc"` -- pins that a repeated keyword is Click's last-wins (`bc`), not two sources, so the new check cannot count one keyword twice.
- `tests/smoke.bats` -- three `expect_configure_failure` tests naming `DiameterPushAVP` and the exact error, one literal byte test each for `push-avp-randuint32-false` and `push-avp-duplicate-octetstring`, one pattern test for `push-avp-rand-zero`, and extend the header comment from four refused configs to seven with the conflicting-value rule -- the comment is the index of what the failure tests prove.
- `tests/README.md` -- the config-table rows for every new config and the configure-path paragraph's count and rule list -- the file currently says only flag and Vendor-Id conflicts are refused.
- `README.md` -- one sentence beside the source list saying two sources together fail configuration, and the element row's "what it does" noting the refusal -- the top-level reference must not imply precedence.

**Acceptance Criteria:**
- Given the rebuilt package, when `CLICK=PREFIX/bin/click bats --tap tests` runs, then it exits 0 with every existing expectation unchanged, including `push-avp`, `push-avp-rand`, the `rand-*` tests and the `randomness-*` tests.
- Given `OCTETSTRING "abc", UINT32 7`, `RANDNUMSTRING 4, RANDHEXSTRING 4`, or `OCTETSTRING "", UINT32 0`, when Click configures the element, then it exits non-zero with a single error naming the two arguments and no packet reaches `Print`.
- Given `RANDNUMSTRING 0` beside `RANDHEXSTRING 4`, when the frame is printed, then it is 32 octets with AVP Length 12 and four hex characters -- a zero count is unused.
- Given `RANDUINT32 false` beside `OCTETSTRING "abc"`, when the frame is printed, then it is byte-identical to `push-avp.click`.
- Given `OCTETSTRING "a", OCTETSTRING "bc"`, when the frame is printed, then it configures with `bc` as the value -- a repeated keyword is not a second source.
- Given the pre-change package at `f9a70d0`, when the nine new configs run, then the six conflict configs configure and print frames while `push-avp-rand-zero`, `push-avp-randuint32-false` and `push-avp-duplicate-octetstring` pass -- the negative control that separates the refusal from the unchanged single-source path.
- Given the installed prefix, when `man DiameterPushAVP` is inspected, then the value paragraph and the three items state the one-source rule and no longer describe precedence.

## Spec Change Log

## Review Triage Log

### 2026-11-17 — Review pass
- verdicts: 23 findings — high 0, medium 0, low 20, false 3, maybe-false 0
- findings:
  - `[low]` `[patch]` The `RANDUINT32 true`, `RANDALPHANUMSTRING` and `RANDALPHASTRING` rows of the presence table are exercised by no config, so deleting a row leaves the suite green — Verified by grep over every config and by the built package; added `push-avp-conflict-octetstring-randuint32` and `push-avp-conflict-randalphanumstring-randalphastring`, and deleting either row now fails its test.
  - `[false]` `[reject]` The keyword-presence reading of "supplied" diverges from the diff's effective-source reading — Refuted: a zero generator count and `RANDUINT32 false` are the documented "unused"/default values, so nothing they would contribute is discarded; `RANDNUMSTRING 0, OCTETSTRING "abc"` emits `abc`. The story entry and man page select the reading.
  - `[low]` `[patch]` The diagnostic is a shared template unlike DiameterEncap's cited literals, and a three-source config names only the first pair — Verified: the three-source probe names `OCTETSTRING` and `UINT32` and exits. The shape difference is intentional because A-10 is not an RFC rule, and the under-report is now pinned by `push-avp-conflict-three` and stated in the man page.
  - `[low]` `[patch]` The man page, README and `tests/README.md` state the rule with different strength, and four generator items never state it — Verified in the diff; patched to "at most one" across all four surfaces and added the rule to the four generator items.
  - `[low]` `[patch]` Only three of the 21 pairs are tested and no positive case covers `RANDUINT32 true` — Same root cause as the verification-gap gap; patched with the two added tests and the three-source pin, which covers every presence-table row.
  - `[false]` `[reject]` Nothing asserts the conformance property because the change is configure-only and disclaims an RFC basis — Refuted: CAP-1's success is the configure outcome, and accepted configurations keep their exact bytes by contract, so there is no wire change to assert.
  - `[false]` `[reject]` The change spans extra documentation surfaces and omits this run's verification evidence and sprint bookkeeping — Refuted: the README documents the new rule, the evidence is in this file's Auto Run Result, and `sprint-status.yaml` is the caller's orchestration state.
  - `[low]` `[patch]` The four `RAND*STRING` items never state the one-source rule and are asymmetric with `OCTETSTRING` — Verified in the diff; patched with one sentence per item.
  - `[low]` `[patch]` "Exactly one" contradicts the legal no-source case and propagates to the error text — Verified: a lone `RANDNUMSTRING 0` prints the 28-octet header-only AVP; patched to "at most one" in the element, the error, both READMEs, the man page and the pinned tests.
  - `[low]` `[patch]` The error asserts a count and names no legal alternative — Same root cause as the wording finding; the message now reads "at most one value source may be supplied".
  - `[low]` `[patch]` Four presence rows have no test, including the boolean — Same root cause as the verification-gap gap; patched with the two conflict configs and their tests.
  - `[low]` `[patch]` No three-source config exists and the deterministic order is recorded only in a private design note — Verified; patched with `push-avp-conflict-three` and a man-page sentence naming the first conflicting pair.
  - `[low]` `[reject]` The refusal ordering against `VENDORSPEC` is unpinned — Verified by probe: `VENDORSPEC true, VENDOR 0, OCTETSTRING, UINT32` reports the value conflict, so the documented order holds; a test would pin an arbitrary message preference with no user-visible harm.
  - `[low]` `[patch]` Repeated keywords are pinned for `OCTETSTRING` only and undocumented on the page — Verified `UINT32 1, UINT32 2` last-wins; the man page now says a repeated keyword is Click's last-wins. No second duplicate config: `push-avp-duplicate-octetstring` already pins that behaviour for a `read_status` argument.
  - `[low]` `[patch]` A configuration that relied on the old documented precedence now fails and nothing records the break — Verified: `OCTETSTRING "", RANDUINT32 true` now refuses. The man page names the new rule and tells that caller to keep only the source it wants; the SPEC-contradiction claim is refuted because CAP-1 mandates the refusal.
  - `[low]` `[patch]` `README.md` states the rule without the sentinel or no-source cases — Verified; patched with at-most-one, the header-only no-source result, and the zero-count/false clause.
  - `[low]` `[reject]` The new conflict tests and table rows split the vendor group — Verified as a placement nit only; entries are individually named, so there is no behavioural or navigation harm, and moving them is pure churn.
  - `[low]` `[patch]` `simple_action()`'s chain is uncommented and the source list is duplicated — Verified; patched with a comment naming the presence table. The shared-table refactor was not done: it adds structure without a current defect.
  - `[low]` `[reject]` The matrix says `b` where the test uses `bc` — Refuted as a behavioural mismatch: both state last-wins and the config pins `bc`; correcting the matrix would edit the read-only intent-contract.
  - `[low]` `[patch]` The `push-avp-no-value` row uses the pre-change two-axis vocabulary — Verified; reworded to "no value source at all (including a lone zero generator count or `RANDUINT32 false`)".
  - `[low]` `[patch]` A caller reading `=item RANDHEXSTRING` learns nothing about the refusal — Same root cause as the generator-item finding; patched by the same sentence, and the `RANDUINT32` item now says false supplies nothing.
  - `[low]` `[patch]` `README.md` presents the rule without the legal no-source case — Same root cause as the README finding; patched by the same rewrite.
  - `[low]` `[reject]` The spec task text says five config-table rows while six were added — Verified; the fix is a spec edit, recorded here rather than patched, and the spec task line was corrected to cover every new config.

## Design Notes

"Supplied" has to be decided per argument because the types differ. `OCTETSTRING` and `UINT32` cannot express absence in their parsed value (`""` and `0` are both meaningful), so presence comes from `Args::read_status()`, the same signal story 4 used for `UINT32`. The generators use zero as their documented absent sentinel -- `=item RANDNUMSTRING` already says "Zero means unused, which is the default" -- and `RANDUINT32` is a boolean whose default is false, so a zero count and a false boolean are not sources. That asymmetry is deliberate: an empty string asks for the headless AVP story 4 pinned, while `RANDNUMSTRING 0` asks for nothing, so counting it would make writing a documented default fail a configuration.

The conflict is reported on the first pair in documented argument order (`OCTETSTRING`, `UINT32`, `RANDUINT32`, `RANDALPHANUMSTRING`, `RANDNUMSTRING`, `RANDALPHASTRING`, `RANDHEXSTRING`), so a three-source config names a deterministic pair. The check runs before `hasUint` and the Vendor-Id refusal because it validates the argument surface itself.

Golden frames from the shared 20-octet request (`01000014 80000118 00000000 00000001 00000002`):

```text
push-avp-randuint32-false:      32 | 01000020 80000118 00000000 00000001 00000002 00000108 0000000b 61626300
push-avp-rand-zero:             32 | 01000020 80000118 00000000 00000001 00000002 00000108 0000000c (3[0-9]|4[1-6]){4}
push-avp-duplicate-octetstring: 32 | 01000020 80000118 00000000 00000001 00000002 00000108 0000000a 62630000
```

`Print`'s label column spacing is not derivable from the source; take the exact `label:   NN | ` prefix from a run of the built package rather than from this table.

## Verification

**Commands:**
- `autoconf && ./configure --with-click=/tmp/opencode/click-mt --prefix=/tmp/opencode/click-mt && make CXXFLAGS="-g -O2 -Wall -Wextra -fPIC -shared" && make install` -- expected: builds with no warnings under `-Wall -Wextra`
- `CLICK=/tmp/opencode/click-mt/bin/click bats --tap tests` -- expected: every test passes, including the nine new ones
- `CLICK=/tmp/opencode/click-mt/bin/click bats --tap --filter 'push-avp|rand-' tests` -- expected: the refusals and the unchanged single-source configs pass together
- Negative control: install the package at `f9a70d0` into a second prefix and run the nine new tests against it -- expected: the six conflict configs configure and print a frame instead of failing, while the three single-source configs pass
- Mutation checks: remove the conflict walk -- expected: the conflict tests fail because the configs configure; count `OCTETSTRING` by `datastring.length() > 0` -- expected: `push-avp-conflict-empty-octetstring-uint32` fails; count a zero `RAND*STRING` as supplied -- expected: `push-avp-rand-zero` fails; delete the `RANDUINT32` or `RANDALPHANUMSTRING` row -- expected: the config that names it fails; restore and rerun green
- Installed page inspection: `man DiameterPushAVP` -- expected: the value paragraph names the one-source rule and the error, and no item calls one source a precedence over another

**Environment:** `/tmp/opencode/click-mt` is Click 2.1 built with `--enable-user-multithread` and already carries the story-4 package, so a plain `make install` overwrites it; `/tmp/opencode/bats-core/bin/bats` is bats-core 1.14.

## Auto Run Result

Status: done

**Change.** `DiameterPushAVP` now refuses a configuration that supplies more than one value source, with the configure-time error `the X and Y arguments cannot be used together: at most one value source may be supplied` naming the first conflicting pair in the documented argument order. A source counts as supplied on its own terms: `OCTETSTRING` and `UINT32` by keyword presence (an empty string and a zero number are values), `RANDUINT32` only when true, and a `RAND*STRING` generator only when its count is above zero. The if/else precedence, every accepted configuration's bytes and the per-packet data path are unchanged. Closes finding A-10 for CAP-1.

**Files changed.**
- `src/diameterpushavp.cc` -- `octetSpecified` captured with `read_status`, a fixed-order presence table checked after `Args().complete()` and before `hasUint` and the Vendor-Id refusal, and a comment on the single-source data path.
- `src/diameterpushavp.hh` -- the precedence paragraph replaced by the at-most-one rule (presence per argument, deterministic first pair, repeated keywords, the legal no-source case, the compatibility consequence), the four generator items and `RANDUINT32` corrected.
- `tests/configs/push-avp-conflict-octetstring-uint32.click`, `...-randnumstring-randhexstring.click`, `...-empty-octetstring-uint32.click`, `...-octetstring-randuint32.click`, `...-randalphanumstring-randalphastring.click`, `...-three.click` -- the six refusals, covering every presence-table row and the first-pair order.
- `tests/configs/push-avp-rand-zero.click`, `push-avp-randuint32-false.click`, `push-avp-duplicate-octetstring.click` -- the other side of the rule, where a sentinel or a repeated keyword is not a second source.
- `tests/smoke.bats` -- nine tests (six `expect_configure_failure`, three byte assertions) and an updated coverage comment.
- `tests/README.md`, `README.md` -- the refused-config count and rule, the config-table rows, and the front-door wording.

**Review.** One pass over four layers: 23 findings, high 0, medium 0, low 20, false 3. Four low entries were patched (16 rows): the "exactly one" wording corrected to "at most one" across the error, both READMEs and the man page; the four generator items and the `RANDUINT32` default documented; the compatibility, repeated-keyword and first-pair sentences added; and the `RANDUINT32 true` and `RANDALPHANUMSTRING`/`RANDALPHASTRING` presence rows plus the three-source order pinned by three new configs. Four low entries were rejected: the arbitrary refusal order against the Vendor-Id check (verified correct, no user-visible harm), test/table grouping churn, the matrix's illustrative `b` versus the shipped `bc` (fixing it would edit the read-only intent-contract), and a spec task-count wording corrected in the spec rather than patched. Three findings were false: the keyword-presence alternative, the configure-only conformance claim, and the documentation-surface/evidence scope observation.

**Follow-up review recommendation: false.** No high or medium entry was patched; every patched entry was low, so the pass converged. Patched counts by verdict: high 0, medium 0, low 4 entries (16 findings), maybe-false 0.

**Verification.**
- `-Wall -Wextra`: clean rebuild of all ten sources, 0 compiler diagnostics.
- `CLICK=/tmp/opencode/click-mt/bin/click bats --tap tests`: 121/121, exit 0, no skips.
- `--filter 'push-avp|rand-'`: 29/29, the refusals and every single-source config together.
- Negative control against an installed `f9a70d0` package: of the nine new tests, the six conflict configs configure and print frames while `push-avp-rand-zero`, `push-avp-randuint32-false` and `push-avp-duplicate-octetstring` pass -- the exact predicted split.
- Mutation checks: disabling the conflict walk fails the conflict tests; counting `OCTETSTRING` by `datastring.length() > 0` fails only the empty-string refusal; counting a zero `RANDNUMSTRING` as supplied fails `push-avp-rand-zero`; deleting the `RANDUINT32` row fails its new config; deleting the `RANDALPHANUMSTRING` row fails its new config. The source was restored and the suite rerun green after each.
- Refusal-order probe: `VENDORSPEC true, VENDOR 0, OCTETSTRING "abc", UINT32 1` reports the value conflict, confirming the documented placement.
- Installed page inspected: the `=d` paragraph states at most one source, the first-pair error, repeated keywords, the no-source case and the compatibility consequence; the four generator items state the rule; `RANDUINT32` says its default supplies nothing.

**Residual risks.** The presence asymmetry is a documented judgement rather than an RFC rule: `OCTETSTRING ""` counts as a source while `RANDNUMSTRING 0` and `RANDUINT32 false` do not, because the generators' zero/false is their documented absent value. Duplicate keyword arguments still silently keep the last value, Click-wide behaviour deferred by story 3. The suite pins every presence-table row, not all 21 source pairs, since one pair per predicate exercises the same walk. A three-source configuration reports only the first conflicting pair, which the man page now states.
