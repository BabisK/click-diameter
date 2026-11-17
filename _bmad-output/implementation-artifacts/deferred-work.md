<!-- BMad's deferred-work queue. Open items only, in the format below; never
     annotate an entry with its outcome. A closed item leaves this file and is
     recorded in the owning spec's Review Triage Log as a `deferred` row, with
     the pull request as evidence. -->

### DW-1: No test pins that a received AVP with M set survives the package's own decode and re-encode, so a regression that clears `mandatory` in `AvpHeader::decode()` stays green.
origin: spec-deferred 8fb89420e31e
location: src/diameter.hh:296
source_spec: `3-add-mandatory-to-diameterpushavp.md`
severity: low
reason: DiameterPopStorePushAVP decodes the popped AVP into its AvpHeader member and re-encodes it when the value is pushed back, and every other AVP walker reads the flags octet, but no committed config carries an AVP with M=1 (`popstorepush-roundtrip.click` uses flags 00). Pre-existing: an M=1 frame was reachable on receive before this story; the story only made it reachable from the package's own writer. Closing it needs a config whose hand-written frame carries flags 40 and a byte assertion over the re-encoded output.
status: open

### DW-2: A repeated keyword argument silently keeps the last value, so `MANDATORY true, MANDATORY false` configures and emits M=0.
origin: spec-deferred 36963783a862
location: src/diameterpushavp.cc:98
source_spec: `3-add-mandatory-to-diameterpushavp.md`
severity: low
reason: Verified against the built package: both orders configure and the second value wins. This is Click's Args behaviour for every keyword argument in every element (VENDOR, CODE, OCTETSTRING included), not something this story introduced; rejecting repeats would need package-wide duplicate detection rather than a change to one element.
status: open

### DW-3: No committed config pins a RANDUINT32 draw of zero, so the `hasUint = uintSpecified || randUInt32` half of the rule is carried by the source rather than by a test.
origin: spec-deferred 5040d4351582
location: src/diameterpushavp.cc:148
source_spec: `4-encode-uint32-0-as-a-four-octet-value.md`
severity: low
reason: The draw is click_random(), which on this driver is glibc's random() over [0, 2^31-1], and no Click test element can force a chosen draw: RandomSeed(SEED n) only calls click_srandom(n), and nothing in the package or in Click exposes the drawn value. The only RANDUINT32 config (tests/configs/randomness-push-avp-uint32.click) asserts two 32-octet frames, which every non-zero draw already satisfies, so a regression that keeps magnitude for the random source (hasUint = uintSpecified, length (hasUint || valueUint > 0) ? 4 : 0) leaves the suite green. The delivered code is correct -- hasUint is true whenever RANDUINT32 is set -- so what is missing is the observation, not the behaviour. What would settle it: a Click element or handler that sets the next click_random() value, or a committed seed whose draw is zero on the RNG in use. A seed search over the whole 32-bit space averages a couple of hits but pins glibc's generator rather than this package's rule, and a sweep started for this story did not produce a zero first draw, so no seed was committed.
status: open

### DW-4: Two other writers of the three-octet message Length still truncate it: DiameterEncap stamps Length 20 + payload with no ceiling, and DiameterPopStorePushAVP adds an AVP's padded length with no ceiling.
origin: spec-deferred 9ab7e2be3759
location: src/diameterencap.cc:97, src/diameterpopstorepushavp.cc:85
source_spec: `8-reject-out-of-range-command-code-and-length.md`
severity: medium
reason: Measured against the installed package: a 16,777,200-octet payload into DiameterEncap produced a 16,777,220-octet frame declaring Length 0x000004, and two maximal DiameterPushAVP messages through DiameterPopStorePushAVP produced a 33,554,404-octet frame declaring Length 16,777,188. Both are pre-existing at d1db4ab, and the resolved intent names DiameterPushAVP for the Length half, so this story does not fix them. Closing them needs a run-time drop in each element, a config per element, and the same documentation sentence the PushAVP page now carries.
status: open

### DW-5: DiameterAvpEncap truncates the three-octet AVP Length (RFC 6733 section 4.1) for a value above 0xFFFFFF - 12.
origin: spec-deferred 111aba44fbf1
location: src/diameteravpencap.cc:54
source_spec: `8-reject-out-of-range-command-code-and-length.md`
severity: medium
reason: header.setLength(headerLength + valueLength) at src/diameteravpencap.cc:54 is unguarded; a 16,777,210-octet payload emits an envelope whose Length field reads 000002. Pre-existing and a different field from the message Length this story guards, so it is deferred rather than patched. Closing it needs a run-time drop and a boundary config, following the PushAVP pattern.
status: open

### DW-6: A RAND*STRING count is unbounded and the value is materialised before the ceiling guard decides to drop, so an always-overflowing config pays its allocation and random draws on every packet.
origin: spec-deferred c139f2b06eb4
location: src/diameterpushavp.cc:21-68 and :228
source_spec: `8-reject-out-of-range-command-code-and-length.md`
severity: low
reason: randString() at src/diameterpushavp.cc:21-68 builds the whole value, then the guard at :228 drops it; a count of 20,000,000 burns roughly 0.4 s and 39 MB per packet, and a larger count fails to allocate. This is a pre-existing argument hazard: at d1db4ab the same count also allocated the value, then emitted a frame with a wrapped Length. The SPEC excludes performance work, and a configure-time cap would add argument surface the intent did not ask for. What would settle it: a configure-time rejection of counts that cannot fit even a 20-octet message, documented in the four RAND*STRING items.
status: open
