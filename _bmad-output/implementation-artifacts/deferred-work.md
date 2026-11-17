<!-- BMad's deferred-work queue. Append open items only, in the three-field
     format that bmad-build records; never annotate an entry with its outcome
     here. A closed item leaves this file and is recorded in the owning spec's
     Review Triage Log as a `deferred` row, with the pull request as evidence.
     Presently empty: every recorded item is closed. -->

### DW-1: No test pins that a received AVP with M set survives the package's own decode and re-encode, so a regression that clears `mandatory` in `AvpHeader::decode()` stays green.
origin: spec-deferred 8fb89420e31e
location: src/diameter.hh:239
source_spec: `3-add-mandatory-to-diameterpushavp.md`
severity: low
reason: DiameterPopStorePushAVP decodes the popped AVP into its AvpHeader member and re-encodes it when the value is pushed back, and every other AVP walker reads the flags octet, but no committed config carries an AVP with M=1 (`popstorepush-roundtrip.click` uses flags 00). Pre-existing: an M=1 frame was reachable on receive before this story; the story only made it reachable from the package's own writer. Closing it needs a config whose hand-written frame carries flags 40 and a byte assertion over the re-encoded output.
status: open

### DW-2: A repeated keyword argument silently keeps the last value, so `MANDATORY true, MANDATORY false` configures and emits M=0.
origin: spec-deferred 36963783a862
location: src/diameterpushavp.cc:87
source_spec: `3-add-mandatory-to-diameterpushavp.md`
severity: low
reason: Verified against the built package: both orders configure and the second value wins. This is Click's Args behaviour for every keyword argument in every element (VENDOR, CODE, OCTETSTRING included), not something this story introduced; rejecting repeats would need package-wide duplicate detection rather than a change to one element.
status: open
