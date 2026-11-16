---
title: 'Story 7: Document every element and fix the README install recipe'
type: 'chore'
created: '2026-11-16'
status: 'done'
review_loop_iteration: 0
followup_review_recommended: false
context: ['{project-root}/AGENTS.md']
warnings: ['oversized']
deferred: []
baseline_revision: 'a5af04b82c776f323bfe1e400a8384195a4e039a'
---

<intent-contract>

## Intent

**Problem:** No element header carries a `=c`/`=d` documentation block, so `make install` runs `click-elem2man` and it writes nothing: `share/man/man7` holds Click's 280 pages and zero Diameter pages, silently and with exit 0 (F-12). A user who installs the package has no manual for any element. The README documents the two-flag install but never says the man pages exist or how to read them, and its Requirements section omits `bats-core`, so the "Check it works" step cannot run on a machine that followed the recipe (F-13).

**Approach:** Give each of the nine element headers a documentation block — `=c` synopsis naming the element and its real argument surface, `=s` one of Click's known categories, a one-line summary, `=d` description covering the element's arguments and its drop/flag/padding contract, and `=h` for the handlers an element owns — so `make install` renders nine pages. Correct the README: name `bats-core` in Requirements, state where the pages land and how to read them, and drop the two closed findings from Known limitations.

## Boundaries & Constraints

**Always:** Every documented argument name, default and behaviour matches the code that parses it; only comments change under `src/`; the nine element names, their arguments and their port counts are untouched; `=s` names a category Click knows, so `click-elem2man` emits no warning naming a Diameter header; the existing 73 tests keep passing byte for byte; zero warnings at `-Wall -Wextra`; tabs outside the doc blocks, doc prose at column 0 as Click's own elements do.

**Never:** No behaviour, argument, port or element change; no `AC_INIT`, include-guard, `<iostream>` or fork work (story 8); no hand-written or committed man pages and no `gzip` artefact in the tree; no new build dependency — the pages come from the `click-elem2man` the recipe already installs; do not edit `SPEC.md` or `findings.md`; do not change `Makefile.in`, `configure.ac` or the element map.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|--------------|---------------------------|----------------|
| MAN_PAGES | `make install` into a prefix that carries Click | Nine `share/man/man7/Diameter*.7click.gz` pages, one per element, plus `elements-diameter.7click.gz` listing all nine | No `click-elem2man: warning:` line naming a Diameter header |
| PAGE_CONTENT | `zcat` or `man` on any element page | SYNOPSIS names the element with its real arguments, `Ports`, `Processing` and `Package: diameter` are present, and DESCRIPTION names every parsed argument | No error expected |
| ARGLESS_ELEMENT | `DiameterDecap`, `DiameterPopAVP`, `DiameterPopStorePushAVP`, `DiameterFlipRequest`, `DiameterAvpDecap` pages | SYNOPSIS is `Element()`; DESCRIPTION states what it strips or rewrites, its drop reasons and its no-op case where it has one | No error expected |
| HANDLERS | `DiameterRatedSource` page | ELEMENT HANDLERS lists `rate`, `limit`, `active`, `count` and `reset` with their read/write kinds | No error expected |
| README_RECIPE | README followed verbatim from a fresh prefix | Click builds, the package configures with `--with-click` and `--prefix`, `make install` succeeds, `require(diameter)` loads, `bats --tap tests` runs, `man -M PREFIX/share/man DiameterEncap` renders | No permission error and no tool the recipe never names |
| README_LIMITS | README after the change | Known limitations names only the package identity, the stale guards and includes, and the fork leftovers | No error expected |

</intent-contract>

## Code Map

- `src/diameterratedsource.hh` -- add the block; args `RATE` (default 10), `LIMIT` (-1), `ACTIVE` (true), `CODE`, `REQUEST` required, `APPID` (0), `STOP` (false) per `src/diameterratedsource.cc:36-44`; emits a bare 20-octet message with no E, P or T and `click_random()` identifiers; handlers at `.cc:219-231` are `rate` rw, `limit` rw, `active` rw, `count` r, `reset` w. Category `basicsources`.
- `src/diameterencap.hh` -- args `CODE`, `REQUEST` required, plus `ERROR`, `PROXIABLE`, `RETRANSMITED`, `APPID` (`src/diameterencap.cc:24-49`); prepends 20 octets, Length counts header plus payload, random `hbh`/`e2e`, rejects E-on-request and T-on-answer. Category `basictransfer`.
- `src/diameterdecap.hh` -- no args; strips 20 octets after `diameter_check_header` and drops on short, Length-mismatch, E-on-request or T-on-answer (`src/diameterdecap.cc:14-27`). Category `basictransfer`.
- `src/diameterpushavp.hh` -- args `CODE` required; `VENDORSPEC` (false), `VENDOR`, `OCTETSTRING`, `UINT32`, `RANDUINT32`, `RANDALPHANUMSTRING`, `RANDNUMSTRING`, `RANDALPHASTRING`, `RANDHEXSTRING`, first branch wins (`src/diameterpushavp.cc:82-141`); appends a padded AVP and updates Length. Category `basicmod`.
- `src/diameterpopavp.hh` -- no args; removes the last AVP, updates Length, forwards a message with no AVP unchanged (`src/diameterpopavp.cc:16-47`). Category `basicmod`.
- `src/diameterpopstorepushavp.hh` -- no args; 1/2 ports; pops and stores the last AVP on the first packet, pushes it back onto the next (`src/diameterpopstorepushavp.cc:26-92`). Category `basicmod`.
- `src/diameterfliprequest.hh` -- no args; R toggles, P is kept both ways, T is cleared producing an answer and E producing a request (`src/diameterfliprequest.cc:14-46`). Category `basicmod`.
- `src/diameteravpencap.hh` -- args `CODE` required; `VENDORID` (0, non-zero selects the 12-octet header), `MANDATORY` (false) per `src/diameteravpencap.cc:20-38`; pads to 4 octets with zeros, Length excludes the pad. Category `basictransfer`.
- `src/diameteravpdecap.hh` -- no args; consumes a whole AVP when octets follow, otherwise forwards the value with padding stripped (`src/diameteravpdecap.cc:14-50`). Category `basictransfer`.
- `README.md:16-23` -- Requirements to extend with `bats-core`; `:44-64` -- the install step and its two-flag explanation, where the man pages belong; `:160-174` -- the element table the pages mirror; `:252-257` -- Known limitations to narrow.
- `tests/smoke.bats:26-41` -- `click` from `CLICK` or `PATH` and `run_config`; the new file mirrors that resolution to find the prefix; `tests/README.md:1-18` -- the "installed package" premise and bats requirement the new file inherits.
- `_bmad-output/specs/spec-diameter-package-hardening/findings.md:86-95` -- read-only F-12/F-13 evidence.
- Read-only upstream behaviour: `click-elem2man` skips a comment with no line starting with `=` and returns early when `=c` is absent, so a page exists exactly where `=c` does; `pkg-Makefile`'s `install-man` runs it with `-L -P diameter -e elementmap.xml` against `elementmap-diameter.xml`, writing `$(mandir)/man7/<Element>.7click.gz`.

## Tasks & Acceptance

**Execution:**
- `src/diameterratedsource.hh`, `src/diameterencap.hh`, `src/diameterdecap.hh`, `src/diameterpushavp.hh`, `src/diameterpopavp.hh`, `src/diameterpopstorepushavp.hh`, `src/diameterfliprequest.hh`, `src/diameteravpencap.hh`, `src/diameteravpdecap.hh` -- one doc block each: `=c` synopsis with exactly the parsed argument names, `=s` the category named above, a one-line summary, `=d` description with `=over 8`/`=item` per keyword, `=a` cross-references between writer and reader, and `=h` only for `DiameterRatedSource`'s five handlers -- F-12, since `=c` is the section `click-elem2man` requires.
- `README.md` -- add `bats-core` to Requirements, state in the install step that `make install` renders nine `Diameter*.7click.gz` pages plus `elements-diameter.7click.gz`, add a short "Documentation" section showing `man -M PREFIX/share/man DiameterEncap` and `man -M PREFIX/share/man elements-diameter` for a prefix that is not on `MANPATH`, and reduce Known limitations to the package identity, the stale guards and includes, and the fork leftovers -- F-13 and CAP-7.
- `tests/manpages.bats` -- new file: resolve the Click prefix from `$CLICK` (as `smoke.bats` does) through `readlink -f` and `dirname` twice, then assert the nine pages exist, each page names its element and every argument the code parses, `DiameterRatedSource` lists its five handlers, and `elements-diameter` lists all nine -- a dropped or stale `=c` block fails the run.
- `tests/README.md` -- document the new file, what it reads (the installed prefix), and the `man -M` fallback it implies.

**Acceptance Criteria:**
- Given a prefix with Click installed, when this package is configured with `--with-click` and `--prefix` and `make install` runs, then `share/man/man7` holds exactly nine `Diameter*.7click.gz` pages and `elements-diameter.7click.gz` lists all nine (CAP-7, F-12).
- Given any of the nine pages, when it is rendered, then it names the element, shows its ports and `Package: diameter`, documents every argument the element parses, and its DESCRIPTION is non-empty.
- Given the `DiameterRatedSource` page, when it is rendered, then ELEMENT HANDLERS names `rate`, `limit`, `active`, `count` and `reset`.
- Given a build of this tree, when `make install` runs, then no `click-elem2man: warning:` line names a Diameter header, so every `=s` category is one Click knows.
- Given the README followed verbatim from a fresh prefix, when each step runs, then Click and the package install without a permission error, `require(diameter)` loads, the suite runs, and `man -M PREFIX/share/man DiameterEncap` renders.
- Given the installed package, when `CLICK=.../bin/click bats --tap tests` runs, then the 73 existing tests pass unchanged and every `manpages.bats` test passes.
- Given the package built against Click master at `-Wall -Wextra`, then zero warnings and no element name, argument or port has moved.

## Spec Change Log

## Review Triage Log

### 2026-11-16 — Review pass
- verdicts: 34 findings — high 0, medium 0, low 29, false 5, maybe-false 0
- findings:
  - `[low]` `[patch]` (blind) `src/diameterratedsource.hh:33` says "CODE, REQUEST, APPID and STOP must be named" while APPID and STOP are optional `read()` keywords with defaults 0 and false — real, and the page's own item entries give those defaults; the sentence now says CODE and REQUEST are required and names APPID and STOP as optional keywords.
  - `[low]` `[reject]` (blind) the `=c` synopses present keyword arguments in positional notation and should use `[I<KEYWORDS>]` — Click's own pages use both forms (`Discard([I<keywords> ACTIVE, BURST])`, `CheckIPHeader([OFFSET, I<keywords> OFFSET, ...])`) and its `read_m` elements (`BeaconSource([, I<KEYWORDS>])`) omit the mandatory names entirely; each page's `=d` labels every keyword with Required/Default, and a positional attempt fails loudly naming the argument, so the rewrite would change notation without changing a user outcome.
  - `[low]` `[patch]` (blind) `src/diameterpushavp.hh:24` calls the AVP Code the "Command Code" — real; the AVP carries the AVP Code, and the same page's item says so, so the sentence now matches.
  - `[low]` `[patch]` (blind) `src/diameterpushavp.hh` never ranks a non-empty OCTETSTRING against RANDUINT32 — real: `datastring` is never cleared, so `OCTETSTRING` wins even with `RANDUINT32 true`, which the "otherwise" clause leaves open; the precedence sentence now names that case.
  - `[low]` `[patch]` (blind) `src/diameterpushavp.hh` lists the drop reasons without "runs past the message end", which `diameter_check_message` can return and the two pop pages name — real; the clause matches its siblings now.
  - `[low]` `[patch]` (blind) `tests/manpages.bats` hardcodes each argument list, so an argument that `configure()` gains cannot be seen, while `tests/README.md` claims a stale block fails — real: the test pins doc to test, not doc to code; the README sentence now says a removed or renamed argument fails and an addition is caught at review.
  - `[low]` `[patch]` (blind) the README and `tests/README.md` prose omit the drop-path and no-AVP assertions the new file also makes — real; both now name them.
  - `[low]` `[patch]` (blind) `README.md` Layout still describes `tests/` as only smoke configs and byte assertions — real; the line now covers the install assertions.
  - `[low]` `[patch]` (blind) the Requirements section never names `perl`, although the pages are rendered by Click's Perl `click-elem2man` — real; Perl joins the requirement list, since the recipe now visibly produces pages through it.
  - `[false]` `[reject]` (blind) the 1.5 bats floor is unnecessary and apt's bats is older — refuted: the seeded tests use `BATS_TEST_TMPDIR`, which is why `tests/README.md` already required 1.5, and CI installs Ubuntu 26.04's bats 1.13.
  - `[low]` `[reject]` (blind) the Design Notes attribute `Can't exec "gzcat"` to extending `elements.7click.gz` when it comes from the per-page compare step — real misattribution, but its only fix edits this build's spec.
  - `[low]` `[reject]` (blind) the Design Notes accept two upstream stderr lines while Verification says "zero warnings", leaving noise and regression indistinguishable — the ambiguity is in this build's spec, whose acceptance criterion already scopes it to warnings naming a Diameter header; editing it is out of bounds.
  - `[low]` `[reject]` (blind) the Code Map quotes the `click-elem2man` invocation without `-m $(DESTDIR)$(mandir)` — real omission in this build's spec; the verification ran the real command and counted the pages where it writes them.
  - `[low]` `[patch]` (blind) the diff leaves the story at `in-progress` and `sprint-status.yaml` at `backlog` — real disagreement; the tracker now says `review` and finalization sets `done`.
  - `[low]` `[patch]` (blind) three pages claim nothing else changes while re-encoding normalizes the reserved flag bits — real for accepted-but-nonconforming input; `DiameterFlipRequest`'s absolute sentence now says every field the header models keeps its value, and the pop pages describe their own writes rather than an absolute no-change claim.
  - `[low]` `[reject]` (edge) a `=c` block deleted and reinstalled over the same prefix leaves the old page, so the suite still passes — real, but only on a reused prefix: Click's `install-man` never unlinks, CI installs the package after restoring a Click-only prefix, and the guard would compare mtimes and add fragility for a case the documented fresh install does not have.
  - `[low]` `[patch]` (edge) the hardcoded argument lists cannot see an argument added to `configure()` — same defect and route as the blind hunter's hardcoded-list row.
  - `[low]` `[patch]` (edge) "APPID and STOP must be named" — same defect and route as the first blind row.
  - `[low]` `[patch]` (edge) "Command Code" for the AVP Code — same defect and route as the blind row.
  - `[false]` `[reject]` (edge) older distros' apt bats cannot satisfy the 1.5 floor — same refutation as the blind floor row: `BATS_TEST_TMPDIR` is the floor and 1.5 is what it arrived in.
  - `[low]` `[patch]` (edge) `page()` inside a pipeline loses its exit status, so a missing page is reported as a missing phrase — real diagnostics bug; the two loops now capture the page text first.
  - `[low]` `[reject]` (edge) `section()` returns empty for a missing heading, indistinguishable from an empty section — no false pass: every caller asserts content, so a missing heading surfaces as a concrete failure; only the message is less specific.
  - `[low]` `[reject]` (edge) `src/diameteravpdecap.hh` does not name the partially padded trailing AVP — the page's general statement covers any amount of trailing padding (`it strips the padding and then the header`), and a partly padded AVP is not something an encoder emits.
  - `[low]` `[patch]` (verification gap) the `=s` category and the one-line summary are asserted nowhere, so a typo'd category ships a warning and a junk `.SS` section and a missing summary ships an entry with no text — pre-verified with both demos; the element-list test now requires each of the nine under one of the three known headings with a non-empty summary.
  - `[low]` `[patch]` (verification gap) the SYNOPSIS argument list is unchecked beyond the element name, so a synopsis that drops APPID ships green — pre-verified by deleting it; `expect_element_page` now requires every argument in the SYNOPSIS as well as the DESCRIPTION.
  - `[low]` `[patch]` (verification gap) `DiameterRatedSource` calls APPID and STOP mandatory — same defect and route as the first row.
  - `[low]` `[patch]` (verification gap) the Layout section still describes only byte assertions — same defect and route as the Layout row.
  - `[false]` `[reject]` (intent) the new tests assert a prefix installed out of band rather than anything this diff creates — refuted: `tests/README.md` has always declared the suite runs against an installed package, every existing config test has the same premise, and CI installs before testing.
  - `[low]` `[patch]` (intent) "one whose block has gone stale fails the run" overclaims — same defect and route as the hardcoded-list row.
  - `[low]` `[patch]` (intent) the RatedSource page makes optional arguments mandatory — same defect and route as the first row.
  - `[low]` `[patch]` (intent) the page calls the AVP Code the Command Code — same defect and route as the blind row.
  - `[low]` `[patch]` (intent) argument fidelity rests on the manual check while the automated tests assert presence of prose — same root as the hardcoded-list row; the new SYNOPSIS assertion narrows it, and the README sentence no longer claims the test sees additions.
  - `[false]` `[reject]` (intent) `oversized` records something unaddressed — refuted: it is the template's own flag for a spec above the 1600-token aim, as stories 1, 2, 5 and 6 also carry.
  - `[false]` `[reject]` (intent) "the 73 existing tests keep passing" is inaccurate because the suite now runs 87 — refuted: the 73 existing tests are unmodified and pass; 14 new ones are added, which is what the clause states.

## Design Notes

- **`=c` is the gate, not `=d`.** `click-elem2man` parses only comments that contain a line starting with `=`, and `process_comment` returns at "section '=c' missing" before writing anything. That is why F-12 is silent: a header with no `=` line is never even considered, and the tool exits 0 having written nothing.
- **`=s` must be a category Click knows.** `one_summary` warns `unknown category shorthand '<name>'` for any lower-case section missing from its `@section_headers` table; `diameter` is not in it, so `=s diameter` warns. The package reuses three of Click's own groups — `basicsources` for the generator, `basictransfer` for adding and stripping framing, `basicmod` for rewriting message content — which also puts the elements in the shared `elements(7click)` list.
- **The man directory is `man7` with the `.7click` suffix.** Click's `pkg-Makefile` fixes that, so the recipe's `share/man/man7` is right; `man` finds the page when the prefix is on `MANPATH` and `man -M` works when it is not.
- **Pre-fix probes** (2026-11-16, `$HOME/click` prefix, this baseline): `make install DESTDIR=$HOME/s7-dest` exits 0, installs `diameter.uo` and the element map, and `find $HOME/s7-dest -path '*share/man*' -type f | wc -l` is 0 with no stderr — F-12. `./configure` without `--with-click` stops with `'/usr/local/share/click/config.mk' not found`, which is the recipe failure F-13 describes. On a probe tree with one header documented, the install wrote `DiameterEncap.7click.gz` and `elements-diameter.7click.gz`, which is the shape the nine pages must take.
- **Two upstream lines are not ours.** On Linux `gzcat` does not exist, so extending an existing `elements.7click.gz` prints `Can't exec "gzcat"`; and reading Click's own element map to extend that page warns `unknown category shorthand 'devices' in UMLSwitch`. Both come from Click's tool and map, so verification accepts them and the acceptance criterion is scoped to warnings naming a Diameter header.
- **The pages are generated, never committed.** `make install` renders them from the headers at install time, so a committed `.gz` would be a second source of truth that silently rots.

## Verification

**Commands:**
- Build Click into a fresh prefix from the pristine baseline archive (`./configure --prefix=$HOME/click-s7 --enable-userlevel --disable-linuxmodule && make -j && make install`) -- expected: exit 0.
- Export this tree to WSL with LF endings, then `autoconf && ./configure --with-click=$HOME/click-s7 --prefix=$HOME/click-s7 && make -j && make install` -- expected: zero warnings, `diameter.uo`, element map, and nine `share/man/man7/Diameter*.7click.gz` pages.
- `ls $HOME/click-s7/share/man/man7/Diameter*.7click.gz | wc -l` -- expected: 9.
- `MANWIDTH=80 man -M $HOME/click-s7/share/man DiameterEncap` and `... elements-diameter` -- expected: the element page renders, the list names all nine.
- `CLICK=$HOME/click-s7/bin/click $HOME/bats-core/bin/bats --tap tests` -- expected: every test passes, including `manpages.bats`.
- `g++ -fsyntax-only -I$HOME/click-s7/include -W -Wall -Wextra src/*.cc` -- expected: no output.

**Manual checks (if no CLI):**
- Read each page against its element's `configure()` and Description and confirm no argument is invented, misnamed or omitted, and that each drop reason, flag rule and padding rule matches the code.

## Auto Run Result

Summary: `make install` now renders a manual page for every element and the README recipe tells a new user how to read them. Each of the nine element headers carries a Click documentation block — `=c` synopsis, `=s` one of Click's own categories, a one-line summary, `=d` description with an `=item` per keyword, `=a` cross-references, and `=h` for `DiameterRatedSource`'s five handlers — so `click-elem2man`, which requires `=c` and wrote nothing at all before, emits `Diameter*.7click.gz` for all nine plus `elements-diameter.7click.gz`. The pages come from the headers at install time, so there is no generated file to keep in step. The README gains `bats-core` and `perl` in Requirements, a paragraph on where the pages land, a Documentation section with the `man` and `man -M` forms, a Layout line that covers the new assertions, and a Known limitations section naming only F-14, F-15 and F-16. Fourteen man-page assertions in `tests/manpages.bats` read the installed prefix the Click binary lives in and pin the page set, every argument in both SYNOPSIS and DESCRIPTION, the five handlers, the six readers' drop path, the two pop elements' no-AVP no-op, and each element's known category and summary in the package list.

Files changed:
- `src/diameterratedsource.hh`, `src/diameterencap.hh`, `src/diameterdecap.hh`, `src/diameterpushavp.hh`, `src/diameterpopavp.hh`, `src/diameterpopstorepushavp.hh`, `src/diameterfliprequest.hh`, `src/diameteravpencap.hh`, `src/diameteravpdecap.hh` — one documentation comment each; no code, argument, port or element change.
- `README.md` — `bats-core` and `perl` requirements, the man-page paragraph in the install step, a Documentation section, the Tests and Layout prose, and Known limitations narrowed to the three open findings.
- `tests/manpages.bats` — new file, 14 tests over the installed `share/man/man7`.
- `tests/README.md` — the new file, the prefix it reads, the `man -M` fallback, and what a stale or added argument does and does not fail.
- `_bmad-output/implementation-artifacts/sprint-status.yaml` — story 1-7 moved to `review`.
- `_bmad-output/specs/spec-diameter-package-hardening/stories/7-document-every-element-and-fix-the-readme-install-recipe.md` — this story spec.

Review findings breakdown: 34 findings — high 0, medium 0, low 29, false 5, maybe-false 0. Patched: 22 rows across 13 distinct fixes, all low — the RatedSource page made APPID and STOP mandatory and the PushAVP page called the AVP Code a Command Code, left a non-empty OCTETSTRING's precedence over `RANDUINT32` open and omitted the AVP-past-end drop reason; the FlipRequest page claimed nothing else changes while re-encoding zeroes the reserved flag bits; the README omitted `perl`, still described `tests/` as only byte assertions, and its Tests prose missed the new drop-path and no-op checks; `tests/README.md` claimed a stale block fails when only a removed or renamed argument does; `tests/manpages.bats` asserted nothing about the SYNOPSIS arguments or the element list's category and summary, and lost a missing page behind a pipeline; and the sprint tracker still said `backlog`. Rejected: 12 — 7 low whose fix edits this build's spec (the Design Notes' `gzcat` attribution and its conflict with "zero warnings", the Code Map's missing `-m`) or would add fragility for a case the fresh install does not have (stale pages on a reused prefix, an mtime guard), no false pass (empty `section()`), a partially padded trailing AVP the general sentence already covers, and synopsis notation Click's own pages do not fix either; 5 false — the 1.5 bats floor is what `BATS_TEST_TMPDIR` requires, the suite's installed-prefix premise is its documented contract, `oversized` is the template's size flag, and the 73 existing tests are unmodified. Deferred: 0.

Follow-up review recommendation: false. Every patched entry was low and none was high or medium, so a first pass has converged.

Verification performed (WSL Ubuntu 26.04, GCC 15.2, Click 2.1 built from the pristine `9197a594b` archive):
- Fresh prefix `$HOME/click-s7`: Click configured with the README's own line, built and installed — 280 man pages and no Diameter page before the package, which is F-12 reproduced at this baseline; `./configure` without `--with-click` stops at `'/usr/local/share/click/config.mk' not found`, the F-13 symptom.
- Package exported with LF endings, then `autoconf && ./configure --with-click=$HOME/click-s7 --prefix=$HOME/click-s7 && make -j && make install` — exit 0, zero compiler warnings, `diameter.uo`, element map and nine `Diameter*.7click.gz` pages plus `elements-diameter.7click.gz`.
- Install stderr: zero `click-elem2man: warning:` lines naming a Diameter header; only Click's own `Can't exec "gzcat"` (nine, one per page) and `unknown category shorthand 'devices' in UMLSwitch`, which come from its tool and element map.
- `man -M $HOME/click-s7/share/man` renders `DiameterEncap`, `DiameterRatedSource`, `DiameterPushAVP`, `DiameterFlipRequest` and `elements-diameter`; the list files the nine under Basic Sources and Sinks, Basic Packet Transfer and Basic Packet Modification, each with a summary.
- Argument forms: `DiameterRatedSource(CODE 280, REQUEST true, ...)` and the mixed `(10, 1, true, CODE 280, REQUEST true, ...)` both run; a fully positional `(10, 1, true, 280, true)` fails naming CODE and REQUEST, which is what the page now says.
- `CLICK=$HOME/click-s7/bin/click bats --tap tests` from the README's step 3, with bats 1.14.0 on `PATH` — 87/87 pass: the 73 existing tests unchanged and 14 new ones.
- `g++ -fsyntax-only -I$HOME/click-s7/include -W -Wall -Wextra src/*.cc` — no output.
- Element map unchanged: seven elements at 1/1, `DiameterPopStorePushAVP` 1/2, `DiameterRatedSource` 0/1.
- Matrix audit: MAN_PAGES (the manifest test), PAGE_CONTENT (nine per-element tests), ARGLESS_ELEMENT (the five argless tests plus the drop-path and no-op tests), HANDLERS (the handler test) and README_LIMITS (the section now names F-14, F-15 and F-16 only) each ran and passed, and README_RECIPE was executed end to end from the fresh prefix: Click build, package configure/install, `require(diameter)` load, the suite, and `man -M`.

Residual risks: `linuxmodule` and `bsdpkg` cannot be built on this host, so their compilability rests on the change adding only comments. Click's `install-man` never unlinks, so on a reused prefix a page left by an earlier install can mask a deleted `=c` block; the suite fails that case only on a fresh install, which is what the recipe and CI produce. `manpages.bats` trusts the installed prefix and derives it from the `readlink -f` of the Click binary, so a wrapper outside the prefix would point at the wrong man directory. The `gzcat` and `UMLSwitch` lines are upstream noise the suite never sees. The CI step that runs the suite is still named "Run the smoke configs" though it now runs both files.