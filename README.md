click-diameter
==============

[![Build and test](https://github.com/BabisK/click-diameter/actions/workflows/build-and-test.yml/badge.svg?branch=master)](https://github.com/BabisK/click-diameter/actions/workflows/build-and-test.yml)

Diameter (RFC 6733) message and AVP handling for the
[Click](https://github.com/kohler/click) modular packet router.

This is an out-of-tree Click package: nine elements that build, take apart and
rewrite Diameter headers and attribute-value pairs (AVPs) inside a Click
configuration. It is byte-level plumbing for test harnesses, traffic
generators and proxies — not a Diameter stack. There is no peer state machine,
no attribute dictionary, no transport handling and no session table; the
elements work on whatever packet reaches their input.

Requirements
------------

- Click 2.1 (upstream `kohler/click` master) with the userlevel driver.
- A C++ compiler, `autoconf` and `make`. Building Click itself also needs
  `libpcap-dev`.
- Linux or WSL. Click has no Windows build; the macOS and FreeBSD module
  targets are configured here but are not exercised by CI.

Build and install
-----------------

Two installs into one prefix: Click goes first, then this package goes into the
same place so that `require(diameter)` can find it.

### 1. Build Click

```sh
git clone https://github.com/kohler/click.git
cd click
./configure --prefix="$HOME/click" --enable-userlevel --disable-linuxmodule
make -j"$(nproc)"
make install
```

`--disable-linuxmodule` keeps the build to the userlevel driver, so no kernel
headers or root privileges are needed.

### 2. Build this package

```sh
git clone https://github.com/BabisK/click-diameter.git
cd click-diameter
autoconf
./configure --with-click="$HOME/click" --prefix="$HOME/click"
make -j"$(nproc)"
make install
```

Both flags matter:

- `--with-click=PREFIX` must name a Click *install* — the configure script
  reads `PREFIX/share/click/config.mk` and stops with `config.mk not found` if
  it is missing.
- `--prefix` should be the same directory. `make install` then puts
  `diameter.uo` in `PREFIX/lib` and the element map in
  `PREFIX/share/click/elementmap-diameter.xml`, where a Click running from that
  prefix will find them. Without `--prefix` the package installs to
  `/usr/local`, which usually fails on permissions.

### 3. Check it works

```sh
bats --tap tests                          # or: CLICK=$HOME/click/bin/click bats --tap tests
```

That runs the smoke configs against an installed package and asserts the bytes;
see [tests/README.md](tests/README.md).

Using it
--------

A configuration that uses these elements starts by loading the package:

```click
require(diameter);
```

Click resolves that against the element map in the prefix it was installed
into, so the package must live beside the Click you run.

### Inspect a message and its AVP

`InfiniteSource` with a `\<...>` literal is a convenient source of exact bytes:
here a 36-byte request (Length `0x24`) whose single AVP carries `hello`.

```click
require(diameter);

InfiniteSource(DATA \<01 00 00 24 80 00 01 10 00 00 00 04 00 00 00 01
                    00 00 00 02 00 00 01 08 00 00 00 0d 68 65 6c 6c
                    6f 00 00 00>, LIMIT 1, STOP true)
-> Print(message, MAXLENGTH 200, CONTENTS HEX)
-> DiameterDecap()
-> Print(body, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
```

```text
message:   36 | 01000024 80000110 00000004 00000001 00000002 00000108 0000000d 68656c6c 6f000000
body:   16 | 00000108 0000000d 68656c6c 6f000000
```

`DiameterDecap` strips the 20-byte header and leaves the AVP; `Print` with
`MAXLENGTH` and `CONTENTS HEX` shows the packet length and its bytes.

### Append an AVP

`DiameterPushAVP` appends an AVP and updates the header's Length field. Applied
to a bare 20-byte request, it produces the same 36 bytes the first example
starts from:

```click
require(diameter);

InfiniteSource(DATA \<01 00 00 14 80 00 01 10 00 00 00 04 00 00 00 01
                     00 00 00 02>, LIMIT 1, STOP true)
-> DiameterPushAVP(CODE 264, OCTETSTRING "hello")
-> Print(message, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
```

```text
message:   36 | 01000024 80000110 00000004 00000001 00000002 00000108 0000000d 68656c6c 6f000000
```

The value can also come from a number (`UINT32` or `RANDUINT32`) or from a
generator that emits exactly N characters from a fixed alphabet:
`RANDALPHANUMSTRING N` (`0`-`9`, `A`-`Z`, `a`-`z`), `RANDNUMSTRING N` (`0`-`9`),
`RANDALPHASTRING N` (`A`-`Z`, `a`-`z`) and `RANDHEXSTRING N` (`0`-`9`, `A`-`F`,
upper case).

### Turn a request into an answer

```click
require(diameter);

InfiniteSource(DATA \<01 00 00 14 80 00 01 10 00 00 00 04 00 00 00 01
                     00 00 00 02>, LIMIT 1, STOP true)
-> DiameterFlipRequest()
-> Print(answer, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
```

```text
answer:   20 | 01000014 00000110 00000004 00000001 00000002
```

The flags byte goes from `80` (R set, a request) to `00` (an answer).

Element reference
-----------------

| Element | In/out | Arguments | What it does |
|---|---|---|---|
| `DiameterRatedSource` | 0/1 | `CODE`, `REQUEST` (required); `RATE` (pps, default 10), `LIMIT`, `ACTIVE`, `APPID`, `STOP` | Emits bare 20-byte messages at a token-bucket rate |
| `DiameterEncap` | 1/1 | `CODE`, `REQUEST` (required); `ERROR`, `PROXIABLE`, `RETRANSMITED`, `APPID` | Prepends a 20-byte Diameter header to the packet |
| `DiameterDecap` | 1/1 | — | Strips the 20-byte header |
| `DiameterPushAVP` | 1/1 | `CODE` (required); `VENDORSPEC`, `VENDOR`; one of `OCTETSTRING`, `UINT32`, `RANDUINT32`, `RANDALPHANUMSTRING N`, `RANDNUMSTRING N`, `RANDALPHASTRING N`, `RANDHEXSTRING N` | Appends an AVP and updates the message Length |
| `DiameterPopAVP` | 1/1 | — | Removes the last AVP and updates the message Length |
| `DiameterPopStorePushAVP` | 1/2 | — | Pops the last AVP from one packet (output 0) and pushes that value back onto the next (output 1) |
| `DiameterFlipRequest` | 1/1 | — | Toggles the request bit, turning a request into an answer and back |
| `DiameterAvpEncap` | 1/1 | `CODE` (required); `VENDORID`, `MANDATORY` | Prepends an AVP header (8 bytes, or 12 with `VENDORID`) and pads the AVP to a 4-octet boundary |
| `DiameterAvpDecap` | 1/1 | — | Strips one AVP: consumes the AVP whole when octets follow it, otherwise forwards its value (header 8 bytes, or 12 following the V bit; padding dropped either way) |

Tests
-----

```sh
bats --tap tests                              # click from PATH
CLICK=$HOME/click/bin/click bats --tap tests   # this package installed there
```

`tests/smoke.bats` runs each config under `tests/configs/` and asserts its exact
output. The `malformed-*` configs assert the drop path instead — exit 0, one
warning naming the element and reason, and no `Print` line. CI runs the same
command on every pull request plus a monthly check against upstream Click
master.

Malformed input is dropped, never forwarded. The six elements that read a
received frame — `DiameterDecap`, `DiameterAvpDecap`, `DiameterFlipRequest`,
`DiameterPushAVP`, `DiameterPopAVP` and `DiameterPopStorePushAVP` — validate it
first and drop it with one `ELEMENT: dropping malformed packet: REASON` line
per packet. Drops are not throttled: a hostile source can flood the log, and
that is accepted.

AVPs are padded to a 4-octet boundary with zero octets, and the AVP Length
counts only the header and the value (RFC 6733 §4.1). `DiameterAvpEncap` adds
that padding and `DiameterAvpDecap` derives it from Length and strips it, so a
message built from the encoder's output passes the message readers and a
sequence of AVPs stays aligned. A standalone AVP that arrives without its
padding still decodes to its value rather than being dropped.

Known limitations
-----------------

These elements are not yet RFC-clean in every path. The defects a user hits
first are listed here; each has a file-and-line description and a reproduction
in `_bmad-output/specs/spec-diameter-package-hardening/findings.md`. The smoke
tests assert today's bytes and the `malformed-*` tests assert the drop path, so
a fix changes a test expectation rather than passing silently.

- **Flag policy is not enforced (F-5, F-10).** RFC 6733 §3 forbids P on an
  answer, yet `DiameterEncap` accepts any flag combination and
  `DiameterFlipRequest` leaves P as it found it, so an answer can keep P. Flags
  start clear now that every header is initialized, but nothing checks what a
  caller then sets.

Layout
------

    configure.ac, Makefile.in   build entry points (autoconf, configure, make run here)
    src/                        element sources: one .cc/.hh pair per element, plus diameter.hh
    tests/                      smoke configs and byte-level assertions

License
-------

This package is distributed under the Click license, the same terms as the
[Click modular router](https://github.com/kohler/click): an MIT license plus a
clause forbidding use of the copyright holders' names in advertising or
publicity without prior written permission. The binding text is in
[LICENSE](LICENSE). Copyright (c) 2014 Intracom Telecom and (c) 2026
Charalampos Kaidos.
