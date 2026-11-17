---
id: SPEC-diameter-rfc-conformance
companions: [findings.md]
sources: []
---

> **Canonical contract.** This SPEC and the files in `companions:` are the complete, preservation-validated contract for what to build, test, and validate. Source documents listed in frontmatter are for traceability — consult them only if you need narrative rationale or prose color this contract intentionally omits.

# Diameter RFC 6733 Conformance

## Why

A pain to solve, with a correctness mandate behind it. The package builds, parses and rewrites Diameter frames, but a source-level audit against RFC 6733 found ten defects that keep its output nonconformant: `DiameterPushAVP` can emit an indeterminate Vendor-Id and hard-wires the `M` bit to zero, `UINT32 0` encodes as a zero-length value, message Length is never required to be a multiple of 4, the Version field is never validated, `V=1` with Vendor-Id 0 is accepted, identifiers collide at realistic rates, and per-packet writes race under SMP. A strict peer is entitled to reject what these elements emit, and a type-aware receiver misreads what they forward. Anyone using the package as a test harness or proxy today produces traffic that only looks like Diameter. The audit is complete; this spec turns it into fixes with before-and-after byte assertions.

## Capabilities

- **CAP-1**
  - **intent:** A caller building an AVP through `DiameterPushAVP` gets an AVP the RFC allows, or a configure error naming the conflicting arguments.
  - **success:** `VENDORSPEC true` without `VENDOR` fails at configure time; `MANDATORY true` emits the `M` bit; `UINT32 0` emits AVP Length 12 with a four-octet zero (16 with the vendor header); `OCTETSTRING ""` stays at Length 8; and any two value sources together (`OCTETSTRING`, `UINT32`, `RANDUINT32`, `RANDALPHANUMSTRING`, `RANDNUMSTRING`, `RANDALPHASTRING`, `RANDHEXSTRING`) fail configure naming both. Each case is pinned by a config under `tests/configs/`.
- **CAP-2**
  - **intent:** Message writers emit only messages the RFC allows: a Length that is a multiple of 4 and fits three octets, and a Command Code that fits three octets.
  - **success:** A 5-octet payload encases to a 28-octet frame with three zero pad octets and Length 28; every emitted frame passes the new alignment check; `CODE` above `0xFFFFFF` fails at configure time in both writers instead of being truncated; and `DiameterPushAVP` drops a message that would exceed the three-octet Length field with a warning instead of wrapping it.
- **CAP-3**
  - **intent:** Every reader drops the frames the RFC calls invalid, so no malformed frame leaves a rewriting element still malformed.
  - **success:** A frame with Version 2, a 25-octet frame whose Length says 25, and an AVP with `V=1` and Vendor-Id 0 are each dropped with a one-line reason naming the defect; `DiameterPushAVP`, `DiameterPopAVP` and `DiameterPopStorePushAVP` cannot re-emit the bad Version; and the existing malformed-input configs still pass.
- **CAP-4**
  - **intent:** Hop-by-Hop and End-to-End identifiers stay unique for at least four minutes at any generation rate, while remaining reproducible from a Click seed.
  - **success:** A seeded run of 240 000 messages at 1 000 per second produces no duplicate Hop-by-Hop and no duplicate End-to-End identifier; a second run with the same `RandomSeed` is byte-identical; and no element calls `srand` or `rand`.
- **CAP-5**
  - **intent:** Element state is safe when Click runs more than one thread.
  - **success:** Two threads feeding one `DiameterPushAVP` produce frames whose AVP Length always matches the AVP they carry, and the element is clean under ThreadSanitizer. Single-threaded output is unchanged.

## Constraints

- Fix only A-1 through A-10. Every C-item in `spec-diameter-capabilities` — extra validation, answer construction, byte-stream framing, richer AVP types, Result-Code and redirect, field access — is out of scope.
- Existing `.click` configurations keep working. Argument changes are additive; a change to an element name, argument or port count updates dependent configs in the same commit.
- `MANDATORY` defaults to false so existing configs keep their exact bytes.
- A malformed frame is dropped with one warning line naming the element and reason, never forwarded or repaired into a plausible message.
- `RandomSeed` still reproduces a run; any counter added for A-7 seeds only from `click_random`.
- The package keeps no persistent state, so identifier uniqueness is guaranteed within a run only; no across-reboot claim is made.
- The build stays warning-free at `-Wall -Wextra`, every declared package target still compiles, and no new dependency is added.
- Each story reproduces its finding with a config under `tests/configs/` before claiming a fix; `findings.md` is source-level evidence, not a run-time observation.
- RFC 6733 (October 2012) is the normative reference. RFC 7075 and RFC 8553 were read; neither imposes an on-the-wire change here.

## Non-goals

- No new elements, no Diameter dictionary, no transport, retransmission or session state.
- No persistent state and no cross-reboot identifier uniqueness.
- No redesign of the argument syntax beyond adding `MANDATORY`.
- No change to anything listed under "Verified-correct behaviour" or "Not defects" in `findings.md`; those are the regression surface.
- No performance work. CI pipeline work is limited to what the thread-safety story needs: building Click with `--enable-user-multithread` so the two-thread configs run (story 10), and a ThreadSanitizer job that gates on `tests/tsan-check.sh` (story 11). No other pipeline change.

## Success signal

On the baseline Click install, the package builds with zero warnings, every A-1 through A-10 repro config fails before its fix and passes after, and the full `tests/configs/` suite exits 0. Well-formed input produces the same bytes it does today, except where a caller opts into `MANDATORY`, or pairs a seeded writer with a `RAND*` generator: the identifier counters consume two draws at initialization instead of two per message, so that generator's values move from the second message on (`randomness-encap-push-avp` pins the new bytes).

## Assumptions

- The findings are accurate at baseline `4a007de`; if line numbers have moved, the story re-reads current code and confirms the byte values with a build before fixing.
- A-1 rejects `VENDORSPEC true` without `VENDOR` at configure time rather than defaulting a vendor identity.
- No committed config depends on non-multiple-of-4 `DiameterEncap` output, so zero-padding changes no existing test bytes.
