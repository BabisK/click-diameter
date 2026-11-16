---
id: SPEC-diameter-package-hardening
companions: [findings.md]
sources: []
---

> **Canonical contract.** This SPEC and the files in `companions:` are the complete, preservation-validated contract for what to build, test, and validate. Source documents listed in frontmatter are for traceability — consult them only if you need narrative rationale or prose color this contract intentionally omits.

# Diameter Package Hardening

## Why

A pain to solve, with a correctness mandate behind it. The `click-diameter` package was extracted from an in-tree copy so it can be consumed out-of-tree, but the review run against upstream Click master found that its happy path works while malformed input can crash, hang, or silently corrupt memory, several elements emit headers and AVP framing that violate RFC 6733, and the package installs without documentation or a working README recipe. Anyone who reuses the package today inherits those defects. The work is deferred by decision, not dismissed: this spec is the record that lets a later session fix and verify each defect without repeating the review.

## Capabilities

- **CAP-1**
  - **intent:** A Click graph built from these elements can be fed malformed or hostile Diameter input and keep running, without allocating past a buffer, looping forever, or writing outside the packet.
  - **success:** The regression configs covering a zero-length AVP, a packet shorter than the 20-byte header, a declared length beyond the packet, and an AVP shorter than its header all exit 0 within a time limit and run clean under AddressSanitizer.
- **CAP-2**
  - **intent:** `DiameterEncap` produces a message another Diameter implementation accepts: version 1, Length counting the whole message, and every header field initialized rather than inherited from uninitialized memory.
  - **success:** Byte assertions on encap output show version `1`, Length equal to the packet length, and identical header bytes across repeated runs.
- **CAP-3**
  - **intent:** AVP encoding and decoding preserve 4-octet alignment, so a receiver can walk a sequence of AVPs without losing its place.
  - **success:** A 5-byte payload encodes to 16 bytes, AvpEncap then AvpDecap returns the original payload, and two consecutive AVPs decode at the offsets a decoder expects.
- **CAP-4**
  - **intent:** The argument surface produces exactly what the argument names promise, including the requested random string length and a hex alphabet with no out-of-range characters.
  - **success:** `RANDALPHANUMSTRING 1` yields a 9-byte AVP, `RANDALPHANUMSTRING 8` yields 16 bytes of data, and a 10 kB sample contains no `G` or `g`.
- **CAP-5**
  - **intent:** Elements that write Diameter flags set them consistently with the message type, so a request never looks like an error and an answer never looks proxiable.
  - **success:** Flipping a request clears R and forces P to 0, and generated requests show E=0.
- **CAP-6**
  - **intent:** A run can be reproduced from a seed, because random field generation uses Click randomness instead of reseeding the process-wide C library RNG.
  - **success:** Two runs with the same Click seed produce identical packets, and no element calls `srand` or `rand`.
- **CAP-7**
  - **intent:** A new user can install the package from a clean Click install without root and read a manual page for every element.
  - **success:** `make install` emits 9 diameter man pages, and following the README from a fresh prefix produces a loadable package with no permission error.
- **CAP-8**
  - **intent:** The package and the fork it came from carry no stale identity or leftovers, so a reader cannot mistake a dead copy for the maintained one.
  - **success:** `AC_INIT` names the package consistently, every include guard matches its filename, no data-path file includes `<iostream>`, no dead element override remains, and the fork's Diameter commit contains only intended changes.

## Constraints

- Verification baseline is upstream `kohler/click` master `9197a594b`, built from a pristine archive; not a release tag.
- The package stays out-of-tree: `--with-click` configure, `diameter.uo` plus `elementmap-diameter.xml`, loadable with `require(diameter)`.
- Element names, argument names, and port counts are frozen; existing `.click` configs must keep parsing and wiring.
- Every package target the Makefile declares (userlevel, linuxmodule, bsdpkg) stays compilable; no userlevel-only headers in packet data-path code.
- Zero warnings at `-Wall -Wextra`, with no new third-party dependency.
- Malformed input is dropped, never forwarded as an empty or partial packet, and never repaired into a plausible-looking message.

## Non-goals

- No new elements, no Diameter dictionary or AVP type database, no connection or session state machine.
- No SCTP or TCP transport, retransmission, or peer state; elements remain stateless packet transformers.
- No performance work and no CI pipeline.
- No redesign of the argument syntax or element graph; the public surface is fixed by constraint.

## Success signal

On a clean upstream-master install, the package builds with zero warnings, the full regression set (happy path plus every malformed case in `findings.md`) runs to exit 0 with no abort or timeout under AddressSanitizer, the byte-level assertions for headers, flags, and AVP alignment pass, `make install` produces 9 man pages, and the README recipe succeeds from a fresh prefix.

## Assumptions

- Port counts in the generated elementmap (1/1, with 1/2 for `DiameterPopStorePushAVP`) are the intended contract; no error output port is added, since that would break the frozen surface.
- A zero-length AVP and a declared length larger than the packet are malformed input, not legitimate data, so dropping is acceptable.
- Happy-path wire behavior is correct except where `findings.md` says otherwise; no other byte-level format change is intended.

## Open Questions

- Should AVP encoder padding bytes be zeroed? RFC 6733 requires receivers to ignore padding but does not mandate zero, and stacks differ on whether nonzero padding is tolerated.
- On a short packet or inconsistent length field, should the element drop silently or also log an error? An error port is ruled out by the frozen port-count constraint.
