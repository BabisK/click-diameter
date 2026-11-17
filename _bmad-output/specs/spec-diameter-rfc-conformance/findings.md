# Review Findings

Evidence for every defect this spec defers. Baseline: `click-diameter` `4a007de`, the commit that closed all sixteen findings of `spec-diameter-package-hardening`. The audit was made by reading `src/` against RFC 6733 (October 2012), RFC 7075 (November 2013) and RFC 8553 (March 2019).

**Every finding below is source-level, not reproduced at run time.** The reproduction configs are proposed in the shape `tests/configs/` uses; none has been executed. Treat the byte values as what the code is written to produce, and confirm them with a build before a story claims a fix.

Severity is impact if the defect reaches a user, not effort to fix. Capability links point into `SPEC.md`, which the spec pass creates from this file; the `CAP-n` ids are proposals and may be renumbered there.

## A-1 — `DiameterPushAVP` reads an uninitialised Vendor-Id (high)

- **Where:** `src/diameterpushavp.cc:79`, `src/diameterpushavp.cc:98-105`
- **Symptom:** `VENDORSPEC true` without `VENDOR` copies an indeterminate stack slot into the 12-octet header. When the garbage is zero the AVP goes out as `V=1, Vendor-Id=0`, which the RFC forbids outright; otherwise the vendor identity is whatever the frame's stack contents happened to be.
- **Cause:** `uint32_t vendorId;` is declared without an initializer and assigned only by `.read("VENDOR", vendorId)`, which writes nothing when the argument is absent. `ah.setVendorId(vendorId)` then reads it. This is a read of an indeterminate value, so the behaviour is undefined, not merely wrong.
- **RFC:** 6733 §4.1.1 — "Since the absence of the Vendor-ID field implies that the AVP in question is not vendor specific, implementations MUST NOT use the value of zero (0) for the Vendor-ID field."
- **Fix:** initialise `vendorId = 0` and reject `VENDORSPEC true` with no `VENDOR` at configure time. `DiameterAvpEncap` already gets this right by keying the V bit off `vendorId != 0`, and is the model to copy.
- **Capability:** CAP-1

## A-2 — The AVP `M` bit is hard-wired to zero (high)

- **Where:** `src/diameterpushavp.cc:96`
- **Symptom:** every AVP appended by `DiameterPushAVP` carries `M=0`, and there is no argument that can set it. Every base-protocol AVP a real message needs is registered with `M=1` — Origin-Host (264), Origin-Realm (296), Destination-Realm (283), Result-Code (268), Session-Id (263) — so a message assembled from this element is nonconformant for all of them and a strict peer is entitled to reject it.
- **Cause:** `ah.setMandatory(false);` is unconditional, and `configure()` has no `MANDATORY` argument. `DiameterAvpEncap` has one (`src/diameteravpencap.cc:23`), so the two writers disagree about the same bit.
- **RFC:** 6733 §4.1 — "The 'M' bit MUST be set according to the rules defined in the application specification that introduces or reuses this AVP."
- **Fix:** add `MANDATORY` to `DiameterPushAVP`, defaulting to false so existing configs keep their bytes, and document it. This is the single change that decides whether the package can emit a conformant message at all.
- **Capability:** CAP-1

## A-3 — `UINT32 0` yields a zero-length AVP instead of a four-octet zero (medium)

- **Where:** `src/diameterpushavp.cc:146`
- **Symptom:** `DiameterPushAVP(CODE 268, UINT32 0)` produces an AVP of Length 8 with no value. The RFC fixes Unsigned32 at Length 12 (16 with the vendor header), so the encoded type is wrong and a type-aware receiver misreads the AVP.
- **Cause:** the value-length expression tests the value rather than its presence: `datastring.length() > 0 ? datastring.length() : (datauint > 0 ? 4 : 0)`. Zero is a legal `UINT32` and a legal `RANDUINT32` draw, and both collapse to "no value".
- **RFC:** 6733 §4.2 — Unsigned32 and Integer32: "The AVP Length field MUST be set to 12 (16 if the 'V' bit is enabled)."
- **Fix:** track whether a numeric value was supplied (a separate `bool hasUint`) and key the length off that, not off `datauint > 0`. Keep the empty-OctetString case (`OCTETSTRING ""`) at Length 8, which §4.2 permits ("at least 8").
- **Capability:** CAP-1

## A-4 — Message Length is never required to be a multiple of 4 (medium)

- **Where:** `src/diameter.hh:318-335` (reader), `src/diameterencap.cc:56-58` (writer)
- **Symptom:** two halves of the same rule. A 25-octet frame whose Length field says 25 passes `DiameterDecap` and `DiameterFlipRequest`, which only compare `declared == length`. And `DiameterEncap` writes `Length = 20 + payload length` with neither padding nor a check, so a 5-octet payload produces exactly such a frame. The package therefore emits frames its own message readers reject (`DiameterPushAVP` fails on the trailing 5 octets as a short AVP header) while its header readers accept them.
- **Cause:** no `% 4` test exists on either side.
- **RFC:** 6733 §3 — "The Message Length field is three octets and indicates the length of the Diameter message including the header fields and the padded AVPs. Thus, the Message Length field is always a multiple of 4."
- **Fix:** add `DIAMETER_CHECK_LENGTH_NOT_ALIGNED` to `diameter_check_header`, and have `DiameterEncap` reject a payload that is not a multiple of 4 at run time rather than zero-pad it. A payload that is not on the boundary cannot be a sequence of padded AVPs, and padding it repairs malformed input into a frame that only looks like a message (SPEC constraint). The rejection is pinned by `tests/configs/encap-unaligned-payload.click`.
- **Capability:** CAP-2, CAP-3

## A-5 — The Version field is never validated (medium)

- **Where:** `src/diameter.hh:318-335`
- **Symptom:** `02 00 00 14 80 00 01 18 …` passes every reader and is forwarded. Worse, every element that rewrites a message — `DiameterPushAVP`, `DiameterPopAVP`, `DiameterPopStorePushAVP`, `DiameterFlipRequest` — round-trips `version` through `DiameterHeader::decode`/`encode` and re-emits the bogus value, so a malformed frame leaves the graph still malformed.
- **Cause:** `diameter_check_header` tests Length and the E/T flags and nothing else. `grep version src/` shows the field is only stored, copied and emitted; `DiameterHeader::getVersion()` has no caller.
- **RFC:** 6733 §3 — "This Version field MUST be set to 1 to indicate Diameter Version 1."
- **Fix:** add `DIAMETER_CHECK_BAD_VERSION` and test `buffer[0] == 1` before anything else in `diameter_check_header`, so every reader inherits it.
- **Capability:** CAP-3

## A-6 — `V=1` with a zero Vendor-Id is accepted on receive (low)

- **Where:** `src/diameter.hh:345-362`
- **Symptom:** the AVP `00 00 01 08 80 00 00 0c 00 00 00 00` — V set, Length 12, Vendor-Id 0 — is accepted by `DiameterAvpDecap` and forwarded as an empty value.
- **Cause:** `diameter_check_avp` uses the V bit to size the header and then never reads `buffer[8..11]`.
- **RFC:** 6733 §4.1.1, as in A-1. This is the receive-side mirror of the same rule.
- **Fix:** add `DIAMETER_CHECK_VENDOR_ID_ZERO`; the check is four bytes and belongs in the same change as A-1 so the writer and the reader agree.
- **Capability:** CAP-3

## A-7 — The End-to-End Identifier cannot meet the four-minute uniqueness rule (medium)

- **Where:** `src/diameterencap.cc:56-57`, `src/diameterratedsource.cc:96-97`
- **Symptom:** both elements draw `hbh` and `e2e` fresh from `click_random()` on every packet. At 1 000 messages per second a four-minute window holds about 240 000 messages; with 32 random bits the collision probability is roughly `n²/2³³`, which is far above one, so a duplicate is effectively certain rather than unlikely. The two fields are also drawn from the same stream and can come out equal.
- **Cause:** random-per-packet is the only generator, and there is no counter, no time component and no way for a caller to supply either identifier.
- **RFC:** 6733 §3 — "Senders of request messages MUST insert a unique identifier on each message. The identifier MUST remain locally unique for a period of at least 4 minutes, even across reboots." The same section prescribes the shape of the fix: the high-order 12 bits of `e2e` may carry the low-order 12 bits of the current time and the low 20 a random value; `hbh` is "normally a monotonically increasing number, whose start value was randomly generated".
- **Fix:** a per-element counter seeded once from `click_random()`, presented with the RFC's twelve/twenty shape but carrying no time component, and a fixed `RandomSeed` reproduces it. This keeps CAP-6 of the hardening spec intact — the seed still comes from Click, so `RandomSeed` still reproduces a run — while making uniqueness a property of the generator instead of a probability. The RFC's optional reboot-time value is not used and no across-reboot claim is made (SPEC constraint).
- **Capability:** CAP-4

## A-8 — Per-packet writes to shared element members race under SMP (medium)

- **Where:** `src/diameterencap.cc:56-58`, `src/diameteravpencap.cc:48-58`, `src/diameterpushavp.cc:121-169`
- **Symptom:** with a router running more than one thread and two upstream tasks feeding the same element, two packets can interleave between `ah.setLength(...)` and `ah.encode(...)`, so one packet is stamped with the other's AVP length. `DiameterPushAVP` additionally mutates `datastring` and `datauint` inside `simple_action`.
- **Cause:** `ah`, `datastring` and `datauint` are element members written per packet. Click does not serialise a push element across threads; the element is responsible for its own state. The single-threaded case is correct, which is why every test passes.
- **RFC:** Not an RFC rule — a Click contract. Listed here because the fix touches the same functions as A-1 through A-3 and is free if done in the same pass.
- **Fix:** build a local `AvpHeader` / `String` / `uint32_t` per packet and leave the members as configuration only. No argument or byte changes.
- **Capability:** CAP-5

## A-9 — `CODE` is truncated silently (low)

- **Where:** `src/diameter.hh:65-67` (storage), `src/diameter.hh:154-156` (encoding)
- **Symptom:** `DiameterEncap(CODE 16777496, REQUEST true)` — `0x01000118` — configures cleanly and emits Command Code `0x000118`, with no error and no warning. `DiameterRatedSource` shares the path.
- **Cause:** `setCode` takes a `uint32_t` and `encode` writes the low three octets. Nothing validates the range at configure time.
- **RFC:** 6733 §3 — Command Code is a three-octet field; §3.1 reserves `0xFFFFFE` and `0xFFFFFF` for experimental use.
- **Fix:** reject `code > 0xFFFFFF` in both writers. Consider the same guard on `Length` in `DiameterPushAVP`, which can grow a message past the three-octet ceiling without noticing.
- **Capability:** CAP-2

## A-10 — Conflicting value arguments resolve silently (low)

- **Where:** `src/diameterpushavp.cc:81-92`, `src/diameterpushavp.cc:121-140`
- **Symptom:** `DiameterPushAVP(CODE 264, OCTETSTRING "abc", UINT32 7)` configures without complaint and emits `abc`; `RANDNUMSTRING 4` beside `RANDHEXSTRING 4` silently takes the first. The user gets a packet they did not ask for and no diagnostic.
- **Cause:** the value sources are read as independent optional arguments and then resolved by `if`/`else` order. The man page documents the precedence, so the behaviour is deliberate, but the precedence is not enforced.
- **RFC:** Not an RFC rule — an argument-surface defect. It matters here because the value determines the encoded AVP type, which is where A-3 and A-2 bite.
- **Fix:** reject mutually exclusive combinations at configure time with an error naming both arguments, as `DiameterEncap` already does for `ERROR` on a request.
- **Capability:** CAP-1

## Verified-correct behaviour (do not regress)

Against well-formed input the package is sound, and every item below is pinned by a config under `tests/configs/`:

- Flags follow §3 and §6.2: E is rejected on a request, T on an answer; P is mirrored in both flip directions; E is cleared when an answer becomes a request and T when a request becomes an answer.
- AVP padding is written as zero octets, excluded from the AVP Length, and derived from Length alone on decode.
- `diameter_check_message` walks every AVP with a padded bound, so a zero-length AVP, an AVP below its header and an AVP past the message end are all dropped rather than looped over or read out of bounds. The alignment rule makes the padded-bound comparison unreachable through the message check; it stays as defence in depth for a caller that walks a buffer without the header check.
- Every reader that touches a message checks Length and flags first; a malformed frame is killed, never forwarded as an empty or partial packet, and each drop logs one line naming the element and the reason.
- `DiameterHeader` and `AvpHeader` both initialize every field, so no writer can emit an indeterminate header byte (F-4 of the hardening spec).
- A message with no AVPs is a no-op for `DiameterPopAVP` and `DiameterPopStorePushAVP` rather than an error.

## Not defects

These read as deviations but are correct, and a story must not "fix" them:

- **Reserved flag bits** (`r r r r`) are ignored on receive and written as zero on re-encode. §3 says they "MUST be set to zero and ignored by the receiver", so both halves are right. `DiameterFlipRequest` clearing them on a frame it rewrites is a consequence of modelling only four bits, and is documented.
- **Non-zero AVP padding** is tolerated by `DiameterAvpDecap`, pinned by `tests/configs/avp-decap-nonzero-pad.click`. §4 calls the pad zero-valued, but a receiver that derives its length from the AVP Length is compliant. A strict mode is a capability (C-1), not a defect.
- **`Length` must equal the packet length.** Correct for a packet-oriented element. It is why the package cannot consume a TCP or SCTP segment, which is a capability gap (C-3), not a bug.
- **P on either type, T on a request and E on an answer** pass through the validators unchanged. §3 permits all three, and a stateless element cannot judge whether a T is a legitimate retransmission.
- **`DiameterPopStorePushAVP` storing only the value** and rebuilding from the retained `AvpHeader` is correct; the header carries the code, the M and V bits and the vendor id, and the value is copied at its unpadded length (F-1 of the hardening spec).

## Reproduction harness

Build (WSL, from a pristine export so the Windows checkout's CRLF cannot reach the Click shell scripts):

```bash
git -C /path/to/click archive 9197a594b | tar -x -C "$HOME/src/click-upstream"
cd "$HOME/src/click-upstream" && ./configure --prefix="$HOME/click-master" --disable-linuxmodule
make -j16 && make install
git -C /path/to/click-diameter archive 4a007de | tar -x -C "$HOME/src/pkg"
cd "$HOME/src/pkg" && autoconf && ./configure --with-click="$HOME/click-master" --prefix="$HOME/click-master"
make && make install
```

Run each config with `$HOME/click-master/bin/click cfg.click`. Every config below passes `MAXLENGTH 200` because `Print` truncates at 24 octets by default.

| Finding | Config body |
|---|---|
| A-1 | `InfiniteSource(DATA \<01 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true) -> DiameterPushAVP(CODE 264, VENDORSPEC true, OCTETSTRING "x") -> Print(x, MAXLENGTH 200, CONTENTS HEX) -> Discard;` — expect AVP flags `80` and a Vendor-Id that changes between runs, or `00 00 00 00` |
| A-2 | Same source, `-> DiameterPushAVP(CODE 264, OCTETSTRING "host")` — expect flags `40`, observe `00` |
| A-3 | Same source, `-> DiameterPushAVP(CODE 268, UINT32 0)` — expect `00 00 01 0c 00 00 00 0c 00 00 00 00`, observe Length `00 00 00 08` and no value |
| A-4 | `InfiniteSource(DATA \<de ad be ef 00>, LIMIT 1, STOP true) -> DiameterEncap(CODE 280, REQUEST true) -> Print(x, MAXLENGTH 200, CONTENTS HEX) -> Discard;` — expect a 24-octet frame with the fifth payload octet dropped or padded, observe 25 octets with Length 25 |
| A-5 | `InfiniteSource(DATA \<02 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true) -> DiameterDecap() -> Print(x, MAXLENGTH 200, CONTENTS HEX) -> Discard;` — expect a drop with a version reason, observe a forwarded 0-octet packet |
| A-6 | `InfiniteSource(DATA \<00 00 01 08 80 00 00 0c 00 00 00 00>, LIMIT 1, STOP true) -> DiameterAvpDecap() -> Print(x, MAXLENGTH 200, CONTENTS HEX) -> Discard;` — expect a drop naming the Vendor-Id, observe a forwarded 0-octet packet |
| A-7 | `DiameterRatedSource(CODE 280, REQUEST true, RATE 1000, LIMIT 240000, STOP true)` piped to a collector that records the `e2e` field; count duplicates. A seeded run (`RandomSeed(SEED 1)`) makes the failure deterministic. |
| A-8 | Two `DiameterRatedSource` elements feeding one `DiameterPushAVP`, run with more than one router thread (`click -t 2`), under ThreadSanitizer or by asserting the AVP Length in every output frame. The single-threaded run is clean, so the repro needs the thread count. |
| A-9 | `InfiniteSource(DATA \<de ad be ef>, LIMIT 1, STOP true) -> DiameterEncap(CODE 16777496, REQUEST true) -> Print(x, MAXLENGTH 200, CONTENTS HEX) -> Discard;` — expect a configure error, observe header code `00 01 18` |
| A-10 | Same source as A-1, `-> DiameterPushAVP(CODE 264, OCTETSTRING "abc", UINT32 7)` — expect a configure error naming both arguments, observe an AVP carrying `abc` |

## Capability summary

The spec pass may regroup these; the mapping is here so no finding is lost.

| Capability | Intent | Findings |
|---|---|---|
| CAP-1 | A writer emits only AVPs the RFC allows: a defined Vendor-Id, the caller's M bit, a type-correct value length, and no silent argument conflicts | A-1, A-2, A-3, A-10 |
| CAP-2 | A writer emits only messages the RFC allows: a Length that is a multiple of 4 and a Command Code that fits three octets | A-4 (writer), A-9 |
| CAP-3 | A reader rejects the frames the RFC calls invalid, so no malformed frame leaves a rewriting element still malformed | A-4 (reader), A-5, A-6 |
| CAP-4 | Identifiers are unique for at least four minutes at any generation rate, and reproducible from a seed | A-7 |
| CAP-5 | Element state is safe when Click runs more than one thread | A-8 |
