# Epics and Stories — click-diameter

> **Index only.** The contract is `_bmad-output/specs/spec-diameter-package-hardening/SPEC.md` plus its companion `findings.md`. This file exists so sprint tracking can enumerate the deferred work; it adds no requirements of its own. If the two disagree, the spec wins.

All eight stories are deferred by explicit user direction: the review is complete and verified, no source change has been made, and remediation happens later. Every story is `backlog` — nothing is ready-for-dev until someone picks it up.

## Epic 1: Diameter package hardening

Bring the out-of-tree Click Diameter package to a state where malformed input cannot crash or corrupt memory, emitted messages conform to RFC 6733, and the package installs with documentation. Execution order follows `stories.yaml`.

### Story 1.1: Make malformed Diameter input safe

Covers CAP-1 and findings F-1 (PopStorePushAVP heap overflow), F-2 (PopAVP infinite loop on a zero-length AVP), F-3 (PushAVP out-of-bounds write), F-6 (decapsulators ignore failed pulls).

### Story 1.2: Give DiameterHeader a real constructor and fix Encap

Covers CAP-2 and finding F-4: version byte and Length are unusable today because `DiameterHeader` has no constructor.

### Story 1.3: Pad AVP encoding to 4 octets

Covers CAP-3 and finding F-7: encode pads, decode strips padding, consecutive AVPs stay aligned.

### Story 1.4: Fix RANDALPHANUMSTRING length and the hex alphabet

Covers CAP-4 and findings F-8 (`> true` boolean comparison) and F-9 (alphabet reaches `G`/`g`).

### Story 1.5: Set request and answer flags per RFC 6733

Covers CAP-5 and findings F-5 (E set on requests) and F-10 (P left set on answers).

### Story 1.6: Use Click randomness instead of reseeding the C RNG

Covers CAP-6 and finding F-11: three elements call `srand`/`rand`, so runs are not reproducible.

### Story 1.7: Document every element and fix the README install recipe

Covers CAP-7 and findings F-12 (zero man pages generated) and F-13 (README omits `--with-click` and `--prefix`).

### Story 1.8: Clean up package identity and fork leftovers

Covers CAP-8 and findings F-14 (`AC_INIT` naming), F-15 (guards, `<iostream>`, dead `simple_action`), and F-16 (the fork still carries `conf/test.click` and `etc/diameter/`).
