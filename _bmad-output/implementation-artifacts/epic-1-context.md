# Epic 1 Context: Diameter package hardening

<!-- Generated from planning artifacts. Regenerate with compile-epic-context if planning docs change. -->

## Goal

Bring the out-of-tree Click Diameter package to a state where malformed or hostile input can no longer crash, hang, or corrupt memory, where emitted messages are wire-correct per RFC 6733, and where a new user can install the package without root and read a man page for every element. The review is already complete and verified; this epic is the deferred remediation of the defects it recorded, so that anyone reusing the package stops inheriting them.

## Stories

- Story 1.1: Make malformed Diameter input safe
- Story 1.2: Give DiameterHeader a real constructor and fix Encap
- Story 1.3: Pad AVP encoding to 4 octets
- Story 1.4: Fix RANDALPHANUMSTRING length and the hex alphabet
- Story 1.5: Set request and answer flags per RFC 6733
- Story 1.6: Use Click randomness instead of reseeding the C RNG
- Story 1.7: Document every element and fix the README install recipe
- Story 1.8: Clean up package identity and fork leftovers

## Requirements & Constraints

**Safety.** A graph built from these elements must survive malformed input: a zero-length AVP, a packet shorter than the 20-byte header, a declared length beyond the packet, and an AVP shorter than its header. None may allocate past a buffer, loop forever, or write outside the packet. Every malformed case must exit 0 within a time limit and run clean under AddressSanitizer.

**Wire conformance.** Encapsulated messages must be acceptable to another Diameter implementation: version 1, a Length counting the whole message, and no field inherited from uninitialized memory. AVP encoding and decoding must preserve 4-octet alignment so a receiver can walk a sequence without losing its place, with zeroed padding. Flag handling must follow RFC 6733: a constructed request never carries E, a constructed answer never carries T, P mirrors in both directions, and a received frame carrying E on a request or T on an answer is dropped. P on either type, E on an answer, and T on a request stay legal.

**Argument surface.** Element arguments must produce exactly what their names promise — the requested random-string length, and a hex alphabet limited to 0-9 and A-F.

**Reproducibility.** A run must be reproducible from a seed, which means random field generation uses Click randomness rather than reseeding the process-wide C library RNG.

**Installability.** `make install` must emit one man page per element (nine), and the README recipe must work from a fresh prefix without root.

**Hygiene.** The package and its source fork must carry no stale identity or leftovers that let a reader mistake a dead copy for the maintained one.

**Constraints.**
- Verification baseline is upstream `kohler/click` master `9197a594b`, built from a pristine archive — not a release tag.
- The package stays out-of-tree, built with `--with-click`, producing `diameter.uo` plus `elementmap-diameter.xml` and loading via `require(diameter)`.
- Existing `.click` configurations must keep working. If a fix forces an element name, argument, or port-count change, the dependent configs change in the same commit.
- Every Makefile target (userlevel, linuxmodule, bsdmodule) stays compilable; no userlevel-only headers in packet data-path code.
- Zero warnings at `-Wall -Wextra`, and no new third-party dependency.
- Malformed input is dropped, never forwarded as an empty or partial packet and never repaired into a plausible-looking message. Each drop emits a one-line warning naming the element and the reason. The log-flood risk from a bad source at line rate is accepted; do not add throttling.
- Out of scope: new elements, a Diameter dictionary or AVP type database, connection or session state, SCTP/TCP transport, retransmission, peer state, performance work, and CI pipeline work. Elements remain stateless packet transformers.

## Technical Decisions

- `DiameterHeader` gets a real constructor that initializes version, flags, code, and both identifiers. Every path that builds a header — encap, rated source, and AVP push — goes through it, so no path can emit indeterminate bytes.
- Message-level validation is centralized in a single header check used by every element that reads a message, rather than repeated per element. That check is where type/flag conflicts are rejected with a named warning.
- AVP padding length is derived from the AVP Length field, never from the padding bytes' content; encoding zeroes the padding.
- Randomness comes from Click's RNG. No element references `srand` or `rand` afterwards.
- Element documentation lives in `=c`/`=d` sections in the element headers; without them `make install` renders nothing.
- Port counts keep their current shape (1/1, 1/2 for `DiameterPopStorePushAVP`, and 0/1 for `DiameterRatedSource`); do not add an error output port.
- Include guards match their filenames, and data-path elements do not include `<iostream>`, which the kernel and BSD targets cannot use.

**Where to look.** `_bmad-output/specs/spec-diameter-package-hardening/findings.md` is the defect catalog: sixteen findings with file, line, symptom, cause, and a reproduction config where one applies, plus a verified-correct behavior list that must not regress. Read it before changing element behavior. Reproduce a defect and capture its failing exit code before fixing it.

**Verification.** Build Click from the pinned baseline, then the package against it, on Linux or WSL. Run the defect repro configs and the happy-path configs under both the plain and AddressSanitizer builds; confirm zero warnings. For installability, install into a fresh prefix, count diameter pages in `share/man/man7`, and follow the README verbatim.

## Cross-Story Dependencies

- The header constructor (Story 1.2) is a prerequisite for correct flags (Story 1.5): the flag bits cannot be pinned until the header initializes them. Story 1.5 also amends encap's acceptance rules and adds the shared received-message check, so it touches the same paths Story 1.2 opens.
- AVP alignment (Story 1.3) and malformed-input safety (Story 1.1) both work on the AVP scan and decode path: a zero-length AVP is exactly the case where a length-derived advance fails to progress, so the two fixes must agree on how the next AVP is located.
- Story 1.8's fork cleanup is a separate commit in the Click repository, not in this package; the package change and the fork revert must land together so only one maintained copy remains.
- Execution order follows `stories.yaml`.
