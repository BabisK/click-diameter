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
asserts the exact bytes the config printed: label, packet length and hex
contents. A wrong length field, a changed flag or an off-by-one is a failed
test, not a silent pass.

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

Expectations record today's bytes. One of them is the known-defect behavior
itself — `avp-roundtrip` emits 13 unpadded bytes (F-7) — and the test says so,
so the story that fixes the defect updates the expectation with the fix.

## known-defects/

Reproductions for defects still open in
`_bmad-output/specs/spec-diameter-package-hardening/findings.md`. They are not
part of `smoke.bats` because they abort, hang, or emit wrong bytes on purpose.
Run one by hand with a timeout:

```sh
timeout 10 click tests/known-defects/f2-popavp-zero-length.click
```

| Config | Finding | Current behavior |
|---|---|---|
| `f1-popstorepushavp-overflow.click` | F-1 | aborts, exit 134, `buffer overflow detected` |
| `f2-popavp-zero-length.click` | F-2 | hangs, killed by the timeout |
| `f3-pushavp-length-field.click` | F-3 | exit 0, AVP written at offset 100, declared length 112 |
| `f4-encap-header.click` | F-4 | exit 0, version byte garbage, Length counts payload only |
| `f6-decap-short-packet.click` | F-6 | exit 0, `Packet::pull 20 > length 4`, empty packet forwarded |
| `f7-avp-padding.click` | F-7 | exit 0, 13 bytes where RFC 6733 requires 16 |

When a fix lands, move its repro into `configs/` with an assertion on the output
instead of leaving it here.
