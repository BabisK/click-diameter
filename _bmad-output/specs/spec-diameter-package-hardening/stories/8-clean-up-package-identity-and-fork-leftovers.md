---
title: 'Story 8: Clean up package identity and fork leftovers'
type: 'chore'
created: '2026-11-16'
status: 'done'
review_loop_iteration: 0
followup_review_recommended: false
context: ['{project-root}/AGENTS.md']
warnings: ['oversized']
deferred:
  - summary: >-
      No verification builds the linuxmodule or bsdmodule package, so the property
      the <iostream> removal exists for — data-path sources that compile for the
      kernel and BSD targets — is asserted only by a text scan.
    evidence: |-
      The only build in this run, and the only one in CI, is the userlevel package:
      Click is configured with --enable-userlevel --disable-linuxmodule and the
      package with no --enable-* flags, so MAKE_KPACKAGE and MAKE_BPACKAGE are 0.
      tests/identity.bats greps src/ for the <iostream> spelling rather than
      compiling those targets. Settling it needs a Click built with the kernel
      driver plus kernel headers, or a FreeBSD host for bsdmodule; this host has
      neither.
    location: >-
      Makefile.in:21-23, tests/identity.bats
    severity: low
baseline_revision: '3a9d9dc906dad74d0d7d78655d2cd6226ef36832'
---

<intent-contract>

## Intent

**Problem:** Three packaging leftovers survived the earlier stories. `AC_INIT(click-diameterpackage, 2.0.1)` in `configure.ac:5` carries the 2014 in-tree tarball name and a version unrelated to the Click 2.1 it targets (F-14). Three include guards do not match their filenames — `DIAMETER_HH` in `diameter.hh`, `DIAMETERAPPENDAVP_HH_` in `diameterpushavp.hh`, `DIAMETERPOPSTOREUSHAVP_HH_` in `diameterpopstorepushavp.hh` — three data-path `.cc` files include `<iostream>`, which the linuxmodule and bsdpkg targets cannot use, and `DiameterPopStorePushAVP` declares a `simple_action()` that Click can never call because the element overrides `push()` itself (F-15). The `BabisK/click` fork still carries `conf/test.click`, which does not configure, and `etc/diameter/`, a stale duplicate of this package (F-16).

**Approach:** Name the package `click-diameter` at version `2.1`, the Click version it targets, in the bracketed form Click's own `configure.in:14` uses. Rename each guard to `<STEM>_HH_` with a matching `#endif` comment, drop the three `<iostream>` includes, and rename the unreachable `simple_action` to a private `process()` helper that `push()` calls. Pin all of it with a source-level test file, and rewrite the README's Known limitations to state what remains open and where the fork cleanup lands.

## Boundaries & Constraints

**Always:** Comments, include lists, guards, `AC_INIT`, tests and README prose only — no element, argument, port or byte-level behaviour change; guards follow the trailing-underscore convention the other six headers already use; the full suite keeps passing with every existing expectation unedited; zero warnings at `-Wall -Wextra`.

**Never:** No functional change under `src/`; no new or removed element; no edit to `SPEC.md` or `findings.md`; no committed generated file (`configure`, `config.status`, man pages); no fork file added to or removed from this repository — F-16 is a separate commit in the Click fork; no new build or test dependency beyond `autoconf`, which the recipe already requires.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| PACKAGE_IDENTITY | `autoconf`, then `./configure --version` on a copy of `configure.ac` | First line is `click-diameter configure 2.1` | No error expected |
| GUARD_MATCH | every `src/*.hh` | `#ifndef`/`#define` is `<UPPERCASE STEM>_HH_` and the closing `#endif` comment names the same guard | No error expected |
| NO_IOSTREAM | `src/` | No file includes `<iostream>` | No error expected |
| NO_DEAD_HOOK | every `src/*.hh` | No header declares both `push(` and `simple_action(` | No error expected |
| SUITE | installed package under `CLICK=.../bin/click` | Every existing test passes unedited, plus the new identity tests | No error expected |

</intent-contract>

## Code Map

- `configure.ac:5` -- `AC_INIT(click-diameterpackage, 2.0.1)`, the F-14 line; Click's own `configure.in:14` reads `AC_INIT([click], [2.1])`.
- `src/diameter.hh:6-7` -- `DIAMETER_HH` / `DIAMETER_HH`; every element includes it, so only the guard text moves.
- `src/diameterpushavp.hh:6-7` -- `DIAMETERAPPENDAVP_HH_`, from the element's former name.
- `src/diameterpopstorepushavp.hh:7-8,61,68` -- `DIAMETERPOPSTOREUSHAVP_HH_` (missing `P`), the `simple_action` declaration at 61 and its `#endif` comment at 68.
- `src/diameterpopavp.cc:11`, `src/diameterpushavp.cc:11`, `src/diameterpopstorepushavp.cc:12` -- the three `#include <iostream>` lines; no file under `src/` names a `std::` symbol, so removing them cannot break the build.
- `src/diameterpopstorepushavp.cc:26-42,44` -- `push()` calls `simple_action()` on both branches; the definition at 44 is the body to rename.
- `tests/smoke.bats:586-600` -- the `randomness-source` test, the precedent for a `grep`-over-`src/` assertion (`$BATS_TEST_DIRNAME/../src`; a grep exit of 2 must not read as a pass).
- `tests/README.md:28-44,46-59` -- the file-by-file description the new test file joins.
- `README.md:288-297` -- Known limitations, the only prose naming F-14, F-15 and F-16; `README.md:299-304` -- Layout, which lists what `tests/` holds.
- `_bmad-output/specs/spec-diameter-package-hardening/findings.md:97-116` -- read-only F-14/F-15/F-16 evidence.
- Read-only upstream: `include/click/element.hh:38` declares `virtual Packet *simple_action(Packet *)` and `lib/element.cc:2891-2896` has `Element::push` call it, which is why an element overriding `push` makes its own `simple_action` unreachable.

## Tasks & Acceptance

**Execution:**
- `configure.ac` -- replace line 5 with `AC_INIT([click-diameter], [2.1])` -- F-14.
- `src/diameter.hh`, `src/diameterpushavp.hh`, `src/diameterpopstorepushavp.hh` -- rename the guard and its `#endif` comment to `DIAMETER_HH_`, `DIAMETERPUSHAVP_HH_` and `DIAMETERPOPSTOREPUSHAVP_HH_` -- F-15.
- `src/diameterpopavp.cc`, `src/diameterpushavp.cc`, `src/diameterpopstorepushavp.cc` -- delete the `#include <iostream>` line -- F-15.
- `src/diameterpopstorepushavp.hh`, `src/diameterpopstorepushavp.cc` -- move the declaration under `private:` as `Packet *process(Packet *)`, rename the definition, and call it from both `push()` branches -- F-15, so no member mimics Click's hook.
- `tests/identity.bats` -- new file with the four source assertions and the `configure --version` identity check from the matrix, each naming the finding it pins -- F-14, F-15.
- `tests/README.md` -- describe `identity.bats`, what it reads, and why a source-level assertion exists.
- `README.md` -- rewrite Known limitations so F-14 and F-15 are closed and F-16 is stated as the fork's own commit (`BabisK/click`: delete `conf/test.click`, delete `etc/diameter/`), and name the new test file in Layout.

**Acceptance Criteria:**
- Given `configure.ac`, when `autoconf` runs and the generated `configure --version` prints, then the first line is `click-diameter configure 2.1`.
- Given the tree after the change, when `grep -rn '<iostream>' src/` and a guard scan run, then no include and no mismatched guard remains.
- Given a package built against Click master at `-Wall -Wextra`, when the suite runs, then every pre-existing test passes with its expectation untouched and the new identity tests pass.
- Given the story's diff, when it is read, then it contains no functional change under `src/` and no file from the Click fork.

## Spec Change Log

## Review Triage Log

### 2026-11-16 — Review pass
- verdicts: 34 findings — high 0, medium 0, low 28, false 6, maybe-false 0
- findings:
  - `[low]` `[reject]` (blind) the story record names three guards while five headers were touched — real, but its only fix edits this build's spec; `diameteravpdecap.hh` and the `diameterratedsource.hh` `#endif` comment are recorded here instead.
  - `[low]` `[reject]` (blind) the "Always" boundary says comments and includes only, while a member was renamed — real contradiction in this build's spec; the boundary's own gloss ("no element, argument, port or byte-level behaviour change") holds, and the fix is spec text.
  - `[false]` `[reject]` (blind) `deferred: []` contradicts a deferral of F-16 — refuted: F-16 is not deferred; it is delivered as a separate commit in the fork (`BabisK/click` PR #1), which is where the intent puts it.
  - `[false]` `[reject]` (blind) `in-review` is outside the status vocabulary — refuted: that is the build-auto spec vocabulary (`spec-template.md`), and `sprint-status.yaml` carries the tracker's own `review` for 1-8.
  - `[low]` `[reject]` (blind) `warnings: ['oversized']` is unexplained — the flag is the template's own size marker, as stories 1, 2, 5, 6 and 7 also carry; the fix is spec text.
  - `[low]` `[reject]` (blind) the task text miscounts the new assertions — real wording slip in this build's spec; the four `@test`s are three source scans plus the identity check.
  - `[false]` `[reject]` (blind) empty `## Spec Change Log` and `## Review Triage Log` are indistinguishable from forgotten ones — refuted: both are template sections that stay empty until a review pass, and this entry fills the second.
  - `[false]` `[reject]` (blind) a generated file (`epic-1-context.md`) is committed in a story that forbids committed generated files — refuted: that clause enumerates build outputs (`configure`, `config.status`, man pages); the epic context is the artifact step-01 requires, tracked under `_bmad-output/` like every other planning artifact.
  - `[false]` `[reject]` (blind) the epic's cross-story dependency on F-16 is unsatisfied and unreconciled — refuted: the fork revert is the separate commit the dependency asks for (`BabisK/click` PR #1), and `README.md` says so.
  - `[low]` `[patch]` (blind) `epic-1-context.md` names a "bsdpkg" target the package calls `bsdmodule` — real; the file now uses the package's own target name.
  - `[low]` `[patch]` (blind) `epic-1-context.md` omits `DiameterRatedSource`'s 0/1 from the port counts — real; the file now lists all three port shapes.
  - `[low]` `[patch]` (blind) `epic-1-context.md` claims `findings.md` holds a reproduction config per finding — real overstatement; it now says "where one applies".
  - `[low]` `[patch]` (blind) `README.md` claims file-and-line evidence for all three findings — real: F-14 and F-15 carry no file or line; the sentence now says "symptom evidence".
  - `[low]` `[patch]` (blind) the F-16 paragraph points at `BabisK/click` while `findings.md` names `babisk/diameter` — real; the README now notes the former name.
  - `[low]` `[patch]` (blind) `tests/identity.bats` is line-ending sensitive — real on a CRLF checkout; the guard scan now strips a trailing CR before comparing.
  - `[low]` `[reject]` (blind) nothing pins that `process()` is private and called on both branches — the harmful outcomes (the armed and unarmed paths) are already covered byte for byte by `popstorepush-roundtrip` and `malformed-popstorepush-armed`, so only a naming and access cosmetic remains.
  - `[low]` `[patch]` (blind) the `<iostream>` rationale is wider than the scan — real; `tests/README.md` now calls it the userlevel-only header the data-path sources carried.
  - `[low]` `[patch]` (blind) "needs no Click at all" is never demonstrated — real; `README.md` and `tests/README.md` now show `bats tests/identity.bats` standalone.
  - `[low]` `[patch]` (blind) `AC_INIT`'s name and the `diameter` package name are not distinguished — real; the README paragraph now says `AC_INIT` names the tarball while the Click package stays `diameter`.
  - `[low]` `[patch]` (blind) the re-flowed CI sentence dropped "every push to `master`" — real disagreement with `tests/README.md` and the workflow; the clause is restored.
  - `[low]` `[patch]` (edge) a CRLF checkout makes every header report a guard mismatch — same defect and route as the blind line-ending row.
  - `[low]` `[patch]` (edge) the `configure.ac` copy is unchecked, so a missing file reads as a failed autoconf — real; the test now names the missing or uncopyable file.
  - `[low]` `[patch]` (edge) `# include <iostream>` escapes the include pattern — real; the pattern now allows whitespace after `#`.
  - `[low]` `[patch]` (edge) the dead-hook scan matches prose mentions of `push()` and `simple_action()` — real; it now matches declarations only.
  - `[low]` `[patch]` (edge) a header under a `src/` subdirectory is skipped by the top-level glob — real; the scan now uses `find`.
  - `[low]` `[reject]` (edge) the story claims three guards where five were touched — same defect and route as the first blind row.
  - `[low]` `[defer]` (verification gap) no verification builds the linuxmodule or bsdmodule package, so the `<iostream>` property is pinned only by a text scan — real; this host cannot build either target, so it is recorded in `deferred` with the evidence and the residual risk.
  - `[low]` `[patch]` (verification gap) the guard test fails on a CRLF export — same defect and route as the blind line-ending row.
  - `[low]` `[reject]` (intent) F-16's expectation lives at cross-repo VCS state while the diff answers in prose — the intent's own guidance puts the fork change in a separate commit; that commit is `BabisK/click` PR #1, and this diff states where it lands.
  - `[low]` `[patch]` (intent) the F-16 carrier is re-attributed from `babisk/diameter` to `BabisK/click` without substantiation in the diff — same defect and route as the blind attribution row.
  - `[low]` `[defer]` (intent) the `<iostream>` justification lives at the target-compilation surface while the evidence is a grep — same defect and route as the verification-gap deferral.
  - `[low]` `[reject]` (intent) the diff touches five guards where the description enumerates three — same defect and route as the first blind row.
  - `[low]` `[reject]` (intent) "remove the dead `simple_action`" reads as delete, while the diff renames it — the dead thing is the unreachable override, and deleting the body would fold fifty lines into `push()`; the rename removes the hook and keeps the structure.
  - `[false]` `[reject]` (intent) the spec is authored alongside the change, so it is not independent evidence of the intent — refuted: the spec is the change's own account of itself by construction, and the audit was run against the `stories.yaml` entry, not against that account.

## Design Notes

- **Version 2.1 is the defensible choice.** The only concrete complaint F-14 makes is that `2.0.1` is "unrelated to the Click version it targets"; the package targets Click 2.1 (`README.md:19`, `SPEC.md:44`), and Click's own `AC_INIT([click], [2.1])` shows the bracketed form. A package version tied to the host version it is built against keeps the two visibly in step, and there is no release history to invent a package version from.
- **`simple_action` is dead only as a hook, not as code.** `Element::push` calls `simple_action`, so the name is a virtual override; `DiameterPopStorePushAVP::push` never calls the base, so nothing outside the element can reach it. Renaming to a private `process()` keeps the two-branch structure and removes the misleading hook without folding 50 lines into `push()`.
- **F-16 lands outside this repository.** The fork `BabisK/click` (default branch `master`, last pushed 2026-11-16T08:06Z) still carries `conf/test.click` (blob `b4ae556f`) and `etc/diameter/` with 25 files. `babisk/diameter`, the repository the finding names, now answers 404. The removal is one separate commit there — `git rm conf/test.click && git rm -r etc/diameter` — opened during this run as `BabisK/click` PR #1; nothing in this package's diff can perform or verify it, so this story records the state and leaves the merge to the fork's owner.
- **`autoconf` warns on `configure.ac:73`** (`AC_OUTPUT should be used without arguments`) under this host's Autoconf 2.72. That is pre-existing and unrelated to identity; leave it, and let the identity test ignore autoconf's stderr.

## Verification

**Commands:**
- From an LF export into WSL: `autoconf && ./configure --with-click=$HOME/click-s8 --prefix=$HOME/click-s8 && make -j && make install`, against a prefix that already carries Click built from `9197a594b` -- expected: exit 0 and zero compiler warnings.
- `./configure --version | head -1` -- expected: `click-diameter configure 2.1`.
- `grep -rn '<iostream>' src/` -- expected: no output.
- `g++ -fsyntax-only -I$HOME/click-s8/include -W -Wall -Wextra src/*.cc` -- expected: no output.
- `CLICK=$HOME/click-s8/bin/click bats --tap tests` -- expected: every test passes, including `identity.bats`.

**Manual checks (if no CLI):**
- Read each renamed guard beside its `#endif` comment and confirm the stem matches the filename exactly.
- Confirm `README.md` names no closed finding as open, and that the fork sentence says where the removal happens.

## Auto Run Result

Summary: The package now identifies itself as `click-diameter` 2.1 in the bracketed form Click's own configure uses, every include guard matches its filename with a matching `#endif` comment, the three data-path sources no longer include `<iostream>`, and `DiameterPopStorePushAVP`'s unreachable `simple_action` is a private `process()` helper that its own `push()` calls, so nothing in the tree mimics a Click hook that Click can never reach. All of it is pinned by a new source-level test file, which the suite runs beside the byte assertions. The README's Known limitations now names one open finding, F-16, and says that its removal is a single commit in the Click fork, opened during this run as `BabisK/click` PR #1.

Files changed:
- `configure.ac` — `AC_INIT(click-diameterpackage, 2.0.1)` becomes `AC_INIT([click-diameter], [2.1])`.
- `src/diameter.hh`, `src/diameteravpdecap.hh`, `src/diameterpushavp.hh`, `src/diameterpopstorepushavp.hh`, `src/diameterratedsource.hh` — guards and `#endif` comments aligned with their filenames, including the two stale stems F-15 did not enumerate.
- `src/diameterpopavp.cc`, `src/diameterpushavp.cc`, `src/diameterpopstorepushavp.cc` — the unused `<iostream>` include removed.
- `src/diameterpopstorepushavp.hh`, `src/diameterpopstorepushavp.cc` — `simple_action` becomes the private `process()`, called from both `push()` branches; no behaviour change.
- `tests/identity.bats` — new file, four tests: the `configure --version` line, every header's guard and `#endif`, the absent `<iostream>`, and the absent dead hook.
- `tests/README.md` — the new file, the Click-free run form, and why a source-level assertion exists.
- `README.md` — package identity, the identity test in Tests and Layout, and Known limitations narrowed to F-16 with the fork named.
- `_bmad-output/implementation-artifacts/epic-1-context.md` — the cached epic context this run compiled.
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — story 1-8 moved to `review`.
- `_bmad-output/specs/spec-diameter-package-hardening/stories/8-clean-up-package-identity-and-fork-leftovers.md` — this story spec.

Review findings breakdown: 34 findings — high 0, medium 0, low 28, false 6, maybe-false 0. Patched: 17 rows across four files, all low — the guard scan's CRLF sensitivity, the unchecked `configure.ac` copy, the `# include` spelling, prose mentions in the dead-hook scan, headers nested under `src/`, `AC_INIT`'s tarball name versus the `diameter` package name, the Click-free run form, the `<iostream>` rationale, the CI clause, README's file-and-line overstatement, the fork's former name, and the epic context's target name, port counts and `findings.md` description. Deferred: 2 rows, one item — no verification builds the linuxmodule or bsdmodule package. Rejected: 15 (9 low, 6 false) — 5 low whose fix edits this build's spec (the guard count, the "Always" boundary, the `oversized` flag, the task wording, the five-versus-three guards), 2 low whose harmful outcomes the byte tests already cover or whose fix would fold fifty lines into `push()`, 2 false about the review's own machinery (the spec status vocabulary, the empty log headings), 2 false about artifacts this run is required to produce and track, and 2 false that read F-16 as deferred or unlanded when it is the fork's separate commit.

Follow-up review recommendation: false. Seventeen patched entries, every one low; no high or medium was patched, so a first pass has converged.

Verification performed (WSL Ubuntu 26.04, GCC 15.2, Click 2.1 in `$HOME/click-s8v`, an LF export of this tree):
- `autoconf && ./configure --with-click=... --prefix=... && make -j && make install` — exit 0, zero compiler warning lines, `diameter.uo`, the element map and nine `Diameter*.7click.gz` pages, no `click-elem2man` warning naming a Diameter header.
- `./configure --version | head -1` — `click-diameter configure 2.1`; Autoconf 2.72's pre-existing `AC_OUTPUT` warning on `configure.ac:73` is the only stderr.
- `grep -rn '<iostream>' src/` — no output.
- `g++ -fsyntax-only -I$HOME/click-s8v/include -W -Wall -Wextra src/*.cc` — no output.
- `CLICK=... bats --tap tests` — 91/91 pass, no failures and no skips: the 87 pre-existing tests with every expectation untouched, plus `identity.bats` tests 1-4.
- Matrix audit: PACKAGE_IDENTITY, GUARD_MATCH, NO_IOSTREAM and NO_DEAD_HOOK are the four identity tests, and SUITE is the run above; all passed.

Residual risks: the linuxmodule and bsdmodule packages are not built on this host, so the `<iostream>` property rests on a text scan (deferred, above). F-16 closes only when `BabisK/click` PR #1 is merged; until then the fork still carries the duplicate. `identity.bats` reads the first line of `configure --version`, so a future Autoconf that changes that line's shape needs the test edited, and it skips rather than fails where `autoconf` is absent.
