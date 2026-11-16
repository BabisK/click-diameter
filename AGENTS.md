<!-- bmad:context -->
<!-- Verified 2026-11-16 against 2459b65. Managed by bmad-project-context; edits inside this block are replaced on refresh. Keep anything you want preserved outside the markers. -->

## click-diameter

Diameter (RFC 6733) message and AVP handling for the Click modular router, packaged
out-of-tree as nine elements in C++ against the Click 2.1 API of upstream master.
The autoconf entry points sit at the repository root and compile `src/`.
Planning artifacts, the contract, and the defect backlog live in `_bmad-output/`.

## Policy

- Never commit to `master`; work on a branch and open a pull request.
- Use Conventional Commits — `feat:`, `fix:`, `chore(scope):`, `docs(spec):` — for subject and body.
- Fix only the defect the active story names. Catalogued defects left alone are deferred work, not oversights.

## Where things are

- Build entry: `configure.ac`, `Makefile.in`. Sources: `src/`, one `.cc`/`.hh` pair per element.
- Read `_bmad-output/specs/spec-diameter-package-hardening/findings.md` before changing element behavior — 16 verified defects with file, line and repro.
- Remediation queue: `stories.yaml` alongside it; status in `_bmad-output/implementation-artifacts/sprint-status.yaml`; the contract is `SPEC.md`.
- Smoke configs in `tests/configs/`, defect repros in `tests/known-defects/`.

## Running and verifying

- Build and run on Linux or WSL only. Click has no Windows build, and CRLF in a Windows checkout breaks its shell scripts, so export the tree and normalize line endings before building from WSL.
- `autoconf && ./configure --with-click=PREFIX --prefix=PREFIX && make && make install`. Both flags matter: without `--with-click` it stops at `config.mk not found`; without `--prefix` it installs to `/usr/local` and fails on permissions.
- Verify with `tests/run.sh PATH_TO_CLICK` against a prefix that already carries this package. There is no `make check`.

## Conventions that differ from defaults

- Indent with tabs, as the existing sources and Click upstream do; spaces only for alignment.
- A new element is a `.cc`/`.hh` pair in `src/` with `EXPORT_ELEMENT` and a class name matching the element name. Discovery recurses from the package root and `-I$(srcdir)/src` already covers the includes, so `Makefile.in` needs no edit.
- Element documentation comes from `=c`/`=d` sections in the header; without them `make install` generates no man page.

## Known pitfalls

- `Print` prints 24 bytes unless `MAXLENGTH` is set — pass `MAXLENGTH 200` or packet dumps misrepresent length.
- `click-compile` needs `-t userlevel`; `--userlevel` is rejected with "you must specify a driver".

<!-- /bmad:context -->
