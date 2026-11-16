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
  - **success:** A 5-byte payload encodes to 16 bytes with zeroed padding, AvpEncap then AvpDecap returns the original payload, and two consecutive AVPs decode at the offsets a decoder expects.
- **CAP-4**
  - **intent:** The argument surface produces exactly what the argument names promise, including the requested random string length and a hex alphabet with no out-of-range characters.
  - **success:** `RANDALPHANUMSTRING 1` yields a 9-byte AVP, `RANDALPHANUMSTRING 8` yields 16 bytes of data, and a 10 kB sample contains no `G` or `g`.
- **CAP-5**
  - **intent:** Elements that write Diameter flags set them consistently with the message type, and elements that read a message reject flags that conflict with its type, so a request never carries E, an answer never carries T, and P mirrors in both directions.
  - **success:** Flipping a proxiable request keeps P and clears T, flipping an error answer keeps P and clears E, and generated requests show E=0 while generated answers show T=0; a received frame carrying E on a request or T on an answer is dropped with a named warning, while P on either type, E on an answer and T on a request pass through.
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
- Existing `.click` configurations must keep working; if a fix requires changing an element name, argument or port count, update the configs in the same change.
- Every package target the Makefile declares (userlevel, linuxmodule, bsdpkg) stays compilable; no userlevel-only headers in packet data-path code.
- Zero warnings at `-Wall -Wextra`, with no new third-party dependency.
- Malformed input is dropped, never forwarded as an empty or partial packet, and never repaired into a plausible-looking message; each drop emits a one-line warning naming the element and the reason.

## Non-goals

- No new elements, no Diameter dictionary or AVP type database, no connection or session state machine.
- No SCTP or TCP transport, retransmission, or peer state; elements remain stateless packet transformers.
- No performance work and no CI pipeline work in this spec; CI is tracked by its own spec.
- No redesign of the argument syntax or element graph; a fix changes them only where it must, with dependent configs updated.

## Success signal

On a clean upstream-master install, the package builds with zero warnings, the full regression set (happy path plus every malformed case in `findings.md`) runs to exit 0 with no abort or timeout under AddressSanitizer, the byte-level assertions for headers, flags, and AVP alignment pass, `make install` produces 9 man pages, and the README recipe succeeds from a fresh prefix.

## Assumptions

- Port counts in the generated elementmap (1/1, with 1/2 for `DiameterPopStorePushAVP`) describe the current shape; a fix may change them only if the `.click` configs relying on that shape change in the same commit.
- A zero-length AVP and a declared length larger than the packet are invalid data — RFC 6733 §4.1 (AVP Length at least 8, or 12 with `V`) and §3 (Length covers the whole message) — so dropping, rather than answering with an error message, is the choice these stateless elements make.
- Happy-path wire behavior is correct except where `findings.md` says otherwise; no other byte-level format change is intended.

## Open Questions

None. Both were resolved on 2026-11-16: padding is zeroed per RFC 6733 §4, and every dropped packet warns.
