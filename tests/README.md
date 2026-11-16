# tests

Click configs that exercise the package. There is no `make check`; these run
against an installed Click that already carries `diameter.uo`.

## Running

```sh
tests/run.sh                 # click from PATH
tests/run.sh ~/click/bin/click
```

`run.sh` runs everything under `configs/` with a 10 s timeout and exits nonzero
if any config fails.

## configs/

Behavior that must keep working. Every config exits 0 today:

| Config | Covers |
|---|---|
| `push-avp.click` | appending an AVP, header length updated |
| `pop-avp.click` | removing the last AVP from a two-AVP message |
| `avp-roundtrip.click` | `DiameterAvpEncap` then `DiameterAvpDecap` returns the payload |
| `flip-request.click` | request bit cleared on a request |
| `decap.click` | stripping the 20-byte header leaves the payload |
| `push-avp-rand.click` | generated value, 8 characters |

## known-defects/

Reproductions for defects still open in
`_bmad-output/specs/spec-diameter-package-hardening/findings.md`. They are not
part of `run.sh` because they abort, hang, or emit wrong bytes on purpose. Run
one by hand with a timeout:

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
