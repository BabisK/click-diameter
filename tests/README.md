# tests

Click configs that exercise the package, with byte-level assertions. There is
no `make check`; these run against an installed Click that already carries
`diameter.uo`.

## Running

Requires [bats-core](https://github.com/bats-core/bats-core) — on the CI image
it comes from `apt-get install -y bats`.

```sh
bats --tap tests                              # click from PATH
CLICK=~/click/bin/click bats --tap tests      # explicit binary
CLICK=~/click/bin/click bats --tap --filter pop-avp tests   # one config
```

`smoke.bats` runs every config under `configs/` with a 10 s timeout, then
asserts the bytes the config printed: label, packet length and hex contents. A
wrong length field, a changed flag or an off-by-one is a failed test, not a
silent pass. The octets that are deliberately random — the `hbh`/`e2e`
identifiers of F-11 — are matched with a regex instead of pinned, and the
`encap` test runs its config a second time to check that every other field comes
back byte for byte. The `malformed-*` configs assert the drop path instead:
exit 0, no `Print` line, and exactly one warning naming the element and reason.

Malformed input is dropped, never forwarded. A drop is asserted with
`expect_drop`, which requires exit 0, exactly one warning of the form
`ELEMENT: dropping malformed packet: REASON`, and no `Print` line; a forwarded
malformed packet or a silent drop fails the run. Drops are not throttled, so a
hostile source can flood the log; that is accepted.

CI runs the same command on every pull request and every push to `master`, plus
monthly against the latest Click master, so a local pass is the same check.

## configs/

Behavior that must keep working. Each config has one test in `smoke.bats`:

| Config | Covers |
|---|---|
| `push-avp.click` | appending an AVP, header length updated |
| `push-avp-rand.click` | generated value, 8 characters |
| `pop-avp.click` | removing the last AVP from a two-AVP message |
| `avp-roundtrip.click` | `DiameterAvpEncap` then `DiameterAvpDecap` returns the payload |
| `flip-request.click` | request bit cleared on a request |
| `decap.click` | stripping the 20-byte header leaves the payload |
| `encap.click` | a 4-octet payload gets a version 1 header whose Length counts the header plus the payload, 24 octets (F-4) |
| `encap-empty.click` | a zero-octet packet gets a 20-octet header, version 1 and Length 20 (F-4) |
| `encap-decap.click` | Encap then Decap forwards the payload instead of dropping it (F-4) |
| `encap-push-pop.click` | Encap then PushAVP grows a 28-octet frame to 44 and PopAVP restores 28 (F-4) |
| `rated-source.click` | a generated message is 20 octets: version 1, Length 20, flags `80`, code `000118`, App-Id 42 |
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

Expectations record today's bytes. One of them is the known-defect behavior
itself — `avp-roundtrip` emits 13 unpadded bytes (F-7) — and the test says so,
so the story that fixes the defect updates the expectation with the fix. The
drop tests are the exception: they assert no forwarded bytes at all, only the
one warning line, so a silent drop or a forwarded malformed packet fails.

## known-defects/

Reproductions for defects still open in
`_bmad-output/specs/spec-diameter-package-hardening/findings.md`. They are not
part of `smoke.bats` because they emit wrong bytes on purpose. Run one by hand
with a timeout:

```sh
timeout 10 click tests/known-defects/f7-avp-padding.click
```

| Config | Finding | Current behavior |
|---|---|---|
| `f7-avp-padding.click` | F-7 | exit 0, 13 bytes where RFC 6733 requires 16 |

When a fix lands, move its repro into `configs/` with an assertion on the output
instead of leaving it here.
