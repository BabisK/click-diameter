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

### DW-3: No committed config pins a RANDUINT32 draw of zero, so the `hasUint = uintSpecified || randUInt32` half of the rule is carried by the source rather than by a test.
origin: spec-deferred 5040d4351582
location: src/diameterpushavp.cc:108
source_spec: `4-encode-uint32-0-as-a-four-octet-value.md`
severity: low
reason: The draw is click_random(), which on this driver is glibc's random() over [0, 2^31-1], and no Click test element can force a chosen draw: RandomSeed(SEED n) only calls click_srandom(n), and nothing in the package or in Click exposes the drawn value. The only RANDUINT32 config (tests/configs/randomness-push-avp-uint32.click) asserts two 32-octet frames, which every non-zero draw already satisfies, so a regression that keeps magnitude for the random source (hasUint = uintSpecified, length (hasUint || valueUint > 0) ? 4 : 0) leaves the suite green. The delivered code is correct -- hasUint is true whenever RANDUINT32 is set -- so what is missing is the observation, not the behaviour. What would settle it: a Click element or handler that sets the next click_random() value, or a committed seed whose draw is zero on the RNG in use. A seed search over the whole 32-bit space averages a couple of hits but pins glibc's generator rather than this package's rule, and a sweep started for this story
status: open
