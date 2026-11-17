# Capability Findings

Evidence for every capability this spec defers. Baseline: `click-diameter` `4a007de`, the commit that closed all sixteen findings of `spec-diameter-package-hardening`.

This file is not a defect list. `spec-diameter-rfc-conformance/findings.md` records ten things the code gets wrong; this file records six things the code cannot do at all. The distinction decides the shape of the work: A-items are edits to existing elements with a before-and-after byte assertion, C-items add arguments and elements and therefore need their own non-goals, their own port-count assumptions and their own test surface.

The file is named `findings.md` in both folders so that `SPEC.md`'s `companions: [findings.md]` resolves the same way in each spec.

**Every item below is a source-level reading of `src/` against RFC 6733, RFC 7075 and RFC 8553.** No proposal has been prototyped, and no byte value in this file has been observed at run time.

Priority is the value to a user of this package — a Click graph that builds, inspects and rewrites Diameter frames for test harnesses and proxies — not the size of the change. Capability links point into `SPEC.md`, which the spec pass creates from this file; the `CAP-n` ids are proposals and may be renumbered there.

## C-1 — Readers validate only part of the rule set (high)

- **Where:** `src/diameter.hh:318-335` (`diameter_check_header`), `src/diameter.hh:345-362` (`diameter_check_avp`), `src/diameter.hh:370-396` (`diameter_check_message`)
- **Gap:** the validator knows six reasons to drop a frame. The RFC supplies more that a stateless element can check without a dictionary. This item covers the three that the conformance spec does **not** already list as defects:
  - **Application-Id consistency.** §3: "The value of the Application-ID field in the header MUST be the same as any relevant Application-Id AVPs contained in the message." §6.9 repeats it for Acct-Application-Id outside CER and CEA. Nothing compares the header field with the contents of Auth-Application-Id (258), Acct-Application-Id (259) or Vendor-Specific-Application-Id (260).
  - **Result-Code and the E bit.** §7: "Result-Code AVP values that are used to report protocol errors MUST only be present in answer messages whose 'E' bit is set." A 3xxx Result-Code in an answer without E, or an E-set answer with no Result-Code at all, currently passes.
  - **Padding octets.** §4: the pad is "a number of zero-valued bytes". A strict mode could reject a non-zero pad. The default must stay tolerant, because `tests/configs/avp-decap-nonzero-pad.click` pins the current behaviour and a receiver that derives the pad from Length is compliant.
- **RFC:** 6733 §3, §4, §6.9, §7.
- **Shape:** three new `DiameterCheck` reasons and three branches in the shared inline validators, plus a `STRICT` argument on the readers if the padding check is opt-in. Every reader inherits the checks for free, which is the point of the current design.
- **Depends on:** A-CAP-3. Version, Length alignment and the zero Vendor-Id are already A-4, A-5 and A-6; this item must not duplicate them.
- **Capability:** CAP-1

## C-2 — The package cannot construct a conformant answer (high)

- **Where:** `src/diameterencap.cc:24-31` (argument surface), `src/diameterratedsource.cc:36-45`; no §6.2 element exists
- **Gap:** §6.2 makes an answer carry the request's Hop-by-Hop **and** End-to-End identifiers, and §3 forbids an agent from modifying End-to-End at all. The only way to preserve them today is `DiameterFlipRequest`, which works on a message already in flight; nothing can *set* them. `DiameterEncap` draws both from `click_random()` on every packet, so it cannot build an answer, and cannot relay a request without rewriting an identifier it must not touch.
  Beyond the header, no element implements the rest of §6.2: add a Result-Code, drop Destination-Host and Destination-Realm, keep Session-Id if present, mirror Proxy-Info AVPs in order. `DiameterFlipRequest` flips one bit and leaves a request's AVPs on what is now an answer.
- **RFC:** 6733 §3 (identifier rules), §6.2 (answer construction), §6.1.9 (relay and proxy request handling).
- **Shape:**
  - `DiameterEncap` gains `HBH`, `E2E` and `ECHO_IDENTIFIERS` (copy both from the incoming packet). This alone turns it into a usable relay builder.
  - A new `DiameterAnswer` element implementing §6.2 as one action: copy HBH and E2E, clear R and T, add Result-Code, strip Destination-Host and Destination-Realm, retain Session-Id, mirror Proxy-Info.
- **Depends on:** the Result-Code encoding from C-5, or a minimal inline encoder inside `DiameterAnswer` if C-5 lands later.
- **Capability:** CAP-2

## C-3 — The package cannot consume a transport byte stream (high)

- **Where:** `src/diameter.hh:318-335` — `diameter_check_header` requires the declared Length to equal the packet length
- **Gap:** Diameter runs over TCP and SCTP (§2.1), where the only framing is the three-octet Length field. A buffer handed up by a transport carries one message, part of one, or several. Every reader in this package rejects anything but the first case, so the elements cannot sit behind a real socket without an external framer.
- **RFC:** 6733 §2.1, §3 (Message Length as the frame boundary).
- **Shape:** a `DiameterFramer` element — input a byte stream, output one packet per complete message, holding the remainder across calls and rejecting a declared Length below 20 or above a configurable ceiling. A `MAXLENGTH` argument is the guard against a hostile length field; without it the element buffers on a peer's word.
- **Capability:** CAP-3

## C-4 — AVP values are limited to OctetString and Unsigned32 (medium)

- **Where:** `src/diameterpushavp.cc:81-92`, `src/diameterpushavp.cc:143-166`
- **Gap:** the only value forms are a literal octet string, a 4-octet number and four random-string generators. RFC 6733 §4.2 defines Integer32, Integer64, Unsigned64, Float32, Float64 and Grouped, and §4.3 defines Address, Time, UTF8String, DiameterIdentity, DiameterURI and Enumerated. A command whose AVPs need an IPv4 address, an NTP timestamp or a 64-bit counter cannot be expressed.
  Grouped AVPs work by accident today — chaining `DiameterAvpEncap` over a packet of AVPs produces a correct Grouped value, because each inner AVP is already padded — but nothing validates the recursion and nothing marks the outer AVP as Grouped.
- **RFC:** 6733 §4.2, §4.3.
- **Shape:** type arguments on `DiameterPushAVP` (`INT32`, `INT64`, `UINT64`, `FLOAT32`, `FLOAT64`, `UTF8STRING`, `ADDRESS`, `TIME`, `DIAMETERIDENTITY`, `DIAMETERURI`, `ENUMERATED`, `GROUPED`), each with the fixed Length the RFC mandates. `ADDRESS` needs the AddressType discriminator (1 = IPv4, 2 = IPv6) and `TIME` the four-octet NTP timestamp. A type-aware decode mode on `DiameterAvpDecap` is a second, separable half.
- **Depends on:** A-2 and A-3. A type argument is meaningless while the M bit is fixed at zero and `UINT32 0` encodes as an empty value.
- **Capability:** CAP-4

## C-5 — Result-Code and redirect semantics are not modelled (medium)

- **Where:** no element or helper; `src/diameter.hh` has no AVP-code constants
- **Gap:** Result-Code (268) is the one AVP every answer must carry, and nothing in the package knows it exists — no way to emit it, read it, or name its values. On top of that, RFC 7075 defines realm-based redirection, which is a self-contained, stateless transformation of a request into an answer and therefore a natural fit for this package:
  - Result-Code **3011**, `DIAMETER_REALM_REDIRECT_INDICATION` (RFC 7075 §3.4).
  - Redirect-Realm, AVP code **620**, type DiameterIdentity (§3.3).
  - The redirect answer sets E, preserves the Hop-by-Hop Identifier, carries Result-Code 3011 and one Redirect-Realm AVP per configured realm (§3.2.1).
  - Redirect-Host-Usage (261) may be added and SHOULD be `REALM_AND_APPLICATION` (3); if it is, Redirect-Max-Cache-Time (262) **MUST** also be present (RFC 7075 §3.2.1, RFC 6733 §6.14).
  - The receiving proxy or client strips Destination-Host and Destination-Realm from the original request and adds a new Destination-Realm (§3.2.2).
- **RFC:** 6733 §6.12, §6.13, §6.14, §7.1; RFC 7075 §3.2–3.4.
- **Shape:** a small `DiameterResultCode` element or helper that emits and parses AVP 268 with named constants (2xxx success, 3xxx protocol error, 4xxx transient, 5xxx permanent, plus 3011), and a `DiameterRedirectRealm` element that performs the §3.2.1 transformation. The proxy-side rewrite of §3.2.2 can be the same element with a `MODE` argument, or a separate `DiameterRedirectFollow`.
- **Depends on:** C-2 for the answer-construction primitive. The Redirect-Realm M and V bits must come from the IANA AVP registry, not be guessed.
- **Capability:** CAP-5

## C-6 — Header and AVP fields are not addressable (medium)

- **Where:** the package has nine elements and none exposes a field; `DiameterDecap` and `DiameterAvpDecap` only remove bytes
- **Gap:** you cannot route, branch or inspect on anything the package parses. Command Code, Application-Id, the four flags and both identifiers are read and then forgotten. AVP access is positional only: `DiameterPopAVP` reaches the last AVP, `DiameterAvpDecap` the first, and nothing reaches the second of three or an AVP by code. For a test-harness package that is a large usability hole — the common task, "assert this message carries a Result-Code of 2001", needs a new config shape rather than a new element.
- **RFC:** Not an RFC rule. This is what makes the RFC behaviour observable.
- **Shape:**
  - `DiameterClassify` — expose Code, AppId, flags, HBH and E2E as packet annotations or read handlers, so `PaintSwitch`-style routing works.
  - `DiameterAvpExtract` / `DiameterAvpRemove` — find an AVP by code, optionally vendor-scoped, and emit its value or drop it, with a `NTH` qualifier for repeats.
  - `DiameterRouteRecord` — append Route-Record (282) and detect a forwarding loop (§6.1.3), the two proxy behaviours most often tested.
- **Capability:** CAP-6

## Not applicable — RFC 8553

RFC 8553 is a Best Current Practice that updates thirty-three documents, RFC 6733 among them, for one reason only: the underscored DNS node names those documents define must be registered in the IANA "Underscored and Globally Scoped DNS Node Names" registry. For Diameter the names in question are the ones RFC 6733 §5.2 already prescribes for peer discovery — `_diameter._tcp`, `_diameters._tcp`, `_diameter._sctp`, `_diameters._sctp`.

There is no on-the-wire change, no new AVP, no new result code, and no behaviour a packet element can implement. This package has no peer discovery, no DNS and no transport (see the hardening spec's non-goals), so RFC 8553 imposes nothing on it.

Recorded here so a later reader does not reopen the question. The single actionable note: if a `DiameterDiscover` element is ever added, those four names are the ones it queries, and they are already registered.

## Dependencies and ordering

C-2 through C-6 are not independent. This order keeps each item buildable on what precedes it:

| Order | Item | Blocked by |
|---|---|---|
| 1 | C-1 | A-CAP-3 (the three validators the conformance spec already fixes) |
| 2 | C-4 | A-2, A-3 |
| 3 | C-2 | C-5's Result-Code encoder, or a minimal inline one |
| 4 | C-5 | C-2 |
| 5 | C-3 | nothing |
| 6 | C-6 | nothing, but it is only useful once C-2 and C-5 exist |

C-3 and C-6 are the only items with no prerequisite, which makes them the natural first slice if this spec is ever split.

## Scope boundary this spec must state

The hardening spec's `SPEC.md` closes with four non-goals that forbid almost everything above, verbatim:

> - No new elements, no Diameter dictionary or AVP type database, no connection or session state machine.
> - No SCTP or TCP transport, retransmission, or peer state; elements remain stateless packet transformers.
> - No performance work and no CI pipeline work in this spec; CI is tracked by its own spec.
> - No redesign of the argument syntax or element graph; a fix changes them only where it must, with dependent configs updated.

C-2, C-3, C-5 and C-6 each add an element, contradicting the first. C-3 contradicts the second. C-2 and C-4 add arguments, which the fourth allows only where a fix must. That is not an accident to be papered over: those non-goals were correct for a spec whose mandate was to make existing behaviour safe. This spec needs its own non-goals, written deliberately, or the two documents will contradict each other in the repository.

Two candidate boundaries, for the spec pass to choose between:

- **Narrow:** C-1, C-2 and C-5 only — the package stays a stateless packet transformer but becomes able to build and recognise a real answer, including a redirect. C-3, C-4 and C-6 stay deferred.
- **Broad:** all six, which makes the package a small Diameter toolkit rather than byte-level plumbing, and retires the "not a Diameter stack" framing in `README.md`.

## What must not regress

Every capability above touches `diameter.hh` or the writer elements, so the conformance work of `spec-diameter-package-hardening` and `spec-diameter-rfc-conformance` is the regression surface:

- The existing `DiameterCheck` reasons keep their meaning, and every reader still drops rather than forwards a malformed frame, with one `ELEMENT: dropping malformed packet: REASON` line.
- AVP padding stays zeroed and excluded from the AVP Length; decode still derives the pad from Length alone.
- Flag policy stays as §3 and §6.2 require: E never on a request, T never on an answer, P mirrored in both directions.
- Existing `.click` configurations keep working. The hardening spec's constraint applies here too: a change to an element name, argument or port count updates the dependent configs in the same commit.
- `RandomSeed` still reproduces a run, so any counter introduced for A-7 or C-3 seeds from `click_random()` and nothing else.
- Zero warnings at `-Wall -Wextra`, and every declared package target (userlevel, linuxmodule, bsdpkg) still compiles — the constraint that keeps `<iostream>` out of the data path.

## Capability summary

The spec pass may regroup these; the mapping is here so no item is lost.

| Capability | Intent | Items |
|---|---|---|
| CAP-1 | A reader rejects every frame the RFC calls invalid that can be judged without a dictionary | C-1 |
| CAP-2 | The package can construct a conformant answer, and can relay a request without touching an identifier it must not modify | C-2 |
| CAP-3 | The package can consume a Diameter byte stream, so its elements can sit behind a real transport | C-3 |
| CAP-4 | An AVP value can be expressed in every basic format and the common derived ones | C-4 |
| CAP-5 | Result-Code and RFC 7075 realm-based redirection can be produced and recognised | C-5 |
| CAP-6 | Header fields and individual AVPs are addressable for inspection and routing | C-6 |
