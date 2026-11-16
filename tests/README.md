# tests

Click configs that exercise the package, with byte-level assertions. There is
no `make check`; these run against an installed Click that already carries
`diameter.uo`.

## Running

Requires [bats-core](https://github.com/bats-core/bats-core) 1.5 or newer — the
seeded tests use `BATS_TEST_TMPDIR` — and a Click that carries the `RandomSeed`
test element, which the `randomness-*` configs load. On the CI image bats comes
from `apt-get install -y bats`.

```sh
bats --tap tests                              # click from PATH
CLICK=~/click/bin/click bats --tap tests      # explicit binary
CLICK=~/click/bin/click bats --tap --filter pop-avp tests   # one config
```

`smoke.bats` runs every config under `configs/` with a 10 s timeout, then
asserts the bytes the config printed: label, packet length and hex contents. A
wrong length field, a changed flag or an off-by-one is a failed test, not a
silent pass. A config that sets no seed varies its `hbh`/`e2e` identifiers per
run, so the test matches them with a regex instead of pinning them, and the
`encap` test runs its config a second time to check that every other field comes
back byte for byte.

The `randomness-*` configs pin `RandomSeed(SEED 12345)`, and their assertions
live in `expect_seeded`, the seeded counterpart of `expect_drop` and
`expect_configure_failure`: each config runs once, then with the seed rewritten
in a copy, then again more than a second later, and requires the two packets of
a run to differ, the two seeds to differ, and the rerun to reproduce the first
run byte for byte. A stream seeded from the wall clock, frozen after one draw or
ignoring the seed fails that. Five configs cover every drawing path changed by
F-11: `randomness-encap` and `randomness-rated-source` for the generated
identifiers, `randomness-rated-source-pull` for the pull path,
`randomness-push-avp` for the generated string and
`randomness-push-avp-uint32` for `RANDUINT32`. The `randomness-source` test is
not a config: it greps `src/` and fails on any `srand`, `rand`, `srandom`,
`random`, `click_srandom` or `click_random_srandom` call, so a reintroduced
reseed fails even though no byte assertion can see `configure()`.

The `rand-*` tests pin the length and the alphabet of each `DiameterPushAVP`
generator; one of them appends 10 kB to the packet, so Click prints its
`expensive Packet::put` advisory beside the `Print` line. The `malformed-*`
configs assert the drop path instead: exit 0, no `Print` line, and exactly one
warning naming the element and reason.

Malformed input is dropped, never forwarded. A drop is asserted with
`expect_drop`, which requires exit 0, exactly one warning of the form
`ELEMENT: dropping malformed packet: REASON`, and no `Print` line; a forwarded
malformed packet or a silent drop fails the run. Drops are not throttled, so
a hostile source can flood the log; that is accepted.

Received frames are validated for flags as well as framing: RFC 6733 §3 forbids
E in a request and T in an answer, so a frame with either is dropped with
`the E bit is set on a request` or `the T bit is set on an answer`. P is legal
on either message type, so it never causes a drop.

A configuration the package refuses is asserted with `expect_configure_failure`,
which requires a non-zero exit, Click's whole configure-failure output for that
config (path and line, the `While configuring` line, the named error, and
`Router could not be initialized!`), and no `Print` line. Only
`encap-error-on-request.click` and `encap-retransmit-on-answer.click` take that
path; every other `encap-*` config configures and prints bytes.

CI runs the same command on every pull request and every push to `master`, plus
monthly against the latest Click master, so a local pass is the same check.

## configs/

Behavior that must keep working. Each config has one test in `smoke.bats`:

| Config | Covers |
|---|---|
| `push-avp.click` | appending an AVP, header length updated |
| `push-avp-rand.click` | generated value, 8 characters |
| `rand-alphanum-one.click` | `RANDALPHANUMSTRING 1` emits one character: AVP Length 9 and three zero pad octets (F-8) |
| `rand-hex-one.click` | `RANDHEXSTRING 1` emits one character rather than an empty AVP (F-8) |
| `rand-hex-alphabet.click` | `RANDHEXSTRING 10000` draws all 10,000 characters from `0`-`9`/`A`-`F` (F-9) |
| `rand-num-four.click` | `RANDNUMSTRING 4` emits four digits: AVP Length 12 |
| `rand-alpha-four.click` | `RANDALPHASTRING 4` emits four letters: AVP Length 12 |
| `pop-avp.click` | removing the last AVP from a two-AVP message |
| `avp-roundtrip.click` | `DiameterAvpEncap` then `DiameterAvpDecap` returns the payload |
| `avp-padding.click` | a 5-octet value pads to a 16-octet AVP: Length 13, three zero octets |
| `avp-padding-two.click` | a 2-octet value pads to 12 octets with two zero octets |
| `avp-padding-one.click` | a 3-octet value pads to 12 octets with one zero octet |
| `avp-padding-none.click` | a 4-octet value needs no padding: 12 octets |
| `avp-padding-empty.click` | an empty value is an 8-octet AVP with no padding |
| `avp-padding-vendor.click` | the 12-octet vendor header plus a 5-octet value pads to 20 octets |
| `avp-two-decode.click` | two consecutive padded AVPs decode at the right offsets |
| `avp-decap-unpadded.click` | a standalone legacy AVP with no padding still decodes |
| `avp-decap-vendor.click` | a well-formed 20-octet vendor AVP decodes to its 5-octet value |
| `avp-decap-nonzero-pad.click` | non-zero pad octets do not change the decoded value |
| `avp-encap-message.click` | Encap then AvpEncap then PopAVP: the encoder's padded AVP passes the message readers |
| `flip-request.click` | request bit cleared on a request |
| `flip-request-p.click` | a proxiable request flips to `40`: R clear, P mirrored (RFC 6733 §6.2) |
| `flip-request-t.click` | a retransmitted request flips to `00`: T and R clear (RFC 6733 §3) |
| `flip-request-pt.click` | flags `d0` flip to `40`: P mirrored, T cleared |
| `flip-answer.click` | an answer's flags go `00` to `80`: R set and no other octet moves |
| `flip-answer-p.click` | an answer with P set flips to `c0`: R set, P kept |
| `flip-answer-e.click` | an error answer flips to `80`: R set, E cleared (RFC 6733 §3) |
| `flip-answer-ep.click` | flags `60` flip to `c0`: P kept, E cleared |
| `decap.click` | stripping the 20-byte header leaves the payload |
| `encap.click` | a 4-octet payload gets a version 1 header whose Length counts the header plus the payload, 24 octets (F-4) |
| `encap-empty.click` | a zero-octet packet gets a 20-octet header, version 1 and Length 20 (F-4) |
| `encap-decap.click` | Encap then Decap forwards the payload instead of dropping it (F-4) |
| `encap-push-pop.click` | Encap then PushAVP grows a 28-octet frame to 44 and PopAVP restores 28 (F-4) |
| `encap-error-on-answer.click` | E on an answer is legal and unchecked: flags `20` |
| `encap-retransmit-on-request.click` | T on a request is not checked: flags `90` |
| `encap-proxiable-on-request.click` | P on a request is legal: flags `c0` |
| `encap-proxiable-on-answer.click` | P on an answer is accepted on the caller's declaration, since Encap has no request to mirror: flags `40` |
| `encap-error-on-request.click` | `ERROR true` on a request rejected at configure time (RFC 6733 §3) |
| `encap-retransmit-on-answer.click` | `RETRANSMITED true` on an answer rejected at configure time (RFC 6733 §3) |
| `rated-source.click` | a generated message is 20 octets: version 1, Length 20, flags `80`, code `000118`, App-Id 42 |
| `rated-source-answer.click` | a generated answer is 20 octets with flags `00`: E, P and T clear |
| `randomness-encap.click` | `RandomSeed(SEED 12345)` with `DiameterEncap`: two 24-octet frames, reproduced across runs, identifiers differ (F-11) |
| `randomness-rated-source.click` | `RandomSeed(SEED 12345)` with `DiameterRatedSource`: two 20-octet frames, reproduced across runs, identifiers differ (F-11) |
| `randomness-push-avp.click` | `RandomSeed(SEED 12345)` with `DiameterPushAVP(RANDHEXSTRING 8)`: two 36-octet frames, reproduced across runs, values differ (F-11) |
| `randomness-push-avp-uint32.click` | `RandomSeed(SEED 12345)` with `DiameterPushAVP(RANDUINT32 true)`: two 32-octet frames, reproduced across runs, values differ (F-11) |
| `randomness-rated-source-pull.click` | `RandomSeed(SEED 12345)` with `Unqueue` forcing `DiameterRatedSource`'s pull path: two 20-octet frames, reproduced across runs, identifiers differ (F-11) |
| `popstorepush-roundtrip.click` | popping an unpadded AVP and pushing it back restores the 44-octet message (F-1) |
| `no-avp.click` | a header-only message forwarded unchanged by both pop elements |
| `malformed-short-packet.click` | a 4-octet packet dropped by `DiameterDecap` (F-6) |
| `malformed-avpdecap-short.click` | a 6-octet packet dropped by `DiameterAvpDecap` (F-6) |
| `malformed-avpdecap-v-short.click` | an 8-octet `V` AVP dropped by `DiameterAvpDecap` (F-6) |
| `malformed-zero-length-avp.click` | a zero-length AVP dropped by `DiameterPopAVP`, no hang (F-2) |
| `malformed-avp-short-length.click` | an AVP length below its header dropped by `DiameterPopAVP` |
| `malformed-avp-past-message.click` | an AVP past the message end dropped by `DiameterPopAVP` |
| `malformed-pushavp-length.click` | a header Length beyond the packet dropped by `DiameterPushAVP` (F-3) |
| `malformed-length-short.click` | a header Length below the packet length dropped by `DiameterPushAVP` |
| `malformed-popstorepush-avp-length.click` | a zero-length AVP dropped by `DiameterPopStorePushAVP` |
| `malformed-popstorepush-armed.click` | a malformed second pass dropped by `DiameterPopStorePushAVP` with an AVP armed |
| `malformed-avp-padding-overhang.click` | a padded AVP running past the message dropped by `DiameterPopAVP` |
| `malformed-avp-trailing-octets.click` | a partial trailing AVP header dropped by `DiameterPopAVP` |
| `malformed-decap-length.click` | a Length mismatch dropped by `DiameterDecap` |
| `malformed-avpdecap-short-length.click` | an AVP length below its header dropped by `DiameterAvpDecap` |
| `malformed-flip-request-short.click` | a 4-octet packet dropped by `DiameterFlipRequest` |
| `malformed-error-on-request.click` | a 24-octet request with E dropped by `DiameterDecap` |
| `malformed-error-on-request-message.click` | the same frame dropped by `DiameterPopAVP` |
| `malformed-error-on-request-push.click` | the same flag on a 20-octet request dropped by `DiameterPushAVP` |
| `malformed-retransmit-on-answer.click` | a 20-octet answer with T dropped by `DiameterFlipRequest` |
| `malformed-retransmit-on-answer-popstorepush.click` | the same flag dropped by `DiameterPopStorePushAVP` |
| `malformed-error-on-request-length.click` | Length 100 and E on the same frame: the Length reason wins |
| `decap-p-on-answer.click` | P on an answer is not an error, the payload is forwarded |
| `decap-t-on-request.click` | T on a request is not an error, the payload is forwarded |
| `pop-avp-error-on-answer.click` | E on an answer passes the AVP walk unchanged |

Expectations record today's bytes. AVPs are padded to a 4-octet boundary with
zero octets and the AVP Length excludes that padding (RFC 6733 §4.1); the
`avp-padding*`, `avp-two-decode`, `avp-decap-*` and `avp-roundtrip` configs pin
that, so a regression to an unpadded AVP fails the run. The drop tests are the
exception: they assert no forwarded bytes at all, only the one warning line, so
a silent drop or a forwarded malformed packet fails. A frame that carries both a
bad Length and a prohibited flag reports the Length reason, because the flag
test runs only once the Length matches. `encap-error-on-request` and
`encap-retransmit-on-answer` assert the configure path instead: a non-zero exit,
Click's whole configure-failure output with the named argument, and no `Print`
line, so an element that accepts the pair fails the run.

## Flag policy

The flag bits follow RFC 6733: §3 forbids E in a request and T in an answer, and
§6.2 sets an answer's P to the same value as the request's. `DiameterFlipRequest`
clears T when it produces an answer and E when it produces a request, and keeps
P in both directions. `DiameterEncap` rejects `ERROR` on a request and
`RETRANSMITED` on an answer at configure time, and accepts `PROXIABLE` on either
type because it has no request to mirror. `DiameterRatedSource` sets none of the
three bits. Every element that reads a message checks the flags through
`diameter_check_header`, so a received E-on-request or T-on-answer is dropped
with `the E bit is set on a request` or `the T bit is set on an answer`. P on
either type, E on an answer and T on a request are not errors: the readers that
only validate forward them unchanged, and the flip, which rewrites flags, keeps
P while clearing whatever bit its new type forbids.

## Decode contract

`DiameterAvpDecap` derives the padding from the AVP Length, never from the
padding octets: `(Length + 3) & ~3` minus `Length` is 0 to 3 octets. When octets
follow the AVP in the packet, it consumes the AVP whole — header, value and
padding — so the next AVP starts at offset 0. When the AVP is the whole packet,
it forwards the value with the padding dropped. A standalone legacy AVP that
carries no padding still decodes to its value rather than being dropped.
