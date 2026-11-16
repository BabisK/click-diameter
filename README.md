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
- A C++ compiler, `autoconf`, `make` and `perl`. Building Click itself also
  needs `libpcap-dev`; `perl` runs the `click-elem2man` that Click installs,
  which renders the element man pages at install time.
- `bats-core` 1.5 or newer to run the test suite. On Debian and Ubuntu it comes
  from `apt-get install -y bats`.
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

`make install` also renders the element man pages with the `click-elem2man` that
the Click install provides: one `Diameter*.7click.gz` page per element plus
`elements-diameter.7click.gz`, all in `PREFIX/share/man/man7`. They are
generated from the `=c`/`=d` blocks in `src/`, so there is nothing to commit and
nothing to keep in step by hand.

### 3. Check it works

```sh
bats --tap tests                          # or: CLICK=$HOME/click/bin/click bats --tap tests
```

That runs the test suite against an installed package: the smoke configs assert
exact bytes, and `manpages.bats` asserts the pages `make install` rendered. See
[tests/README.md](tests/README.md).

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

InfiniteSource(DATA \<01 00 00 14 c0 00 01 10 00 00 00 04 00 00 00 01
                     00 00 00 02>, LIMIT 1, STOP true)
-> DiameterFlipRequest()
-> Print(answer, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
```

```text
answer:   20 | 01000014 40000110 00000004 00000001 00000002
```

The flags byte goes from `c0` (`R` and `P` set, a proxiable request) to `40`:
the flip clears R and keeps P, because RFC 6733 §6.2 sets an answer's P to the
same value as the request's. The other two bits are policed in the same pass: T
is cleared when a request becomes an answer and E when an answer becomes a
request, per §3.

Element reference
-----------------

| Element | In/out | Arguments | What it does |
|---|---|---|---|
| `DiameterRatedSource` | 0/1 | `CODE`, `REQUEST` (required); `RATE` (pps, default 10), `LIMIT`, `ACTIVE`, `APPID`, `STOP` | Emits bare 20-byte messages at a token-bucket rate; it never sets E, P or T, so a generated request carries R alone and a generated answer none |
| `DiameterEncap` | 1/1 | `CODE`, `REQUEST` (required); `ERROR`, `PROXIABLE`, `RETRANSMITED`, `APPID` | Prepends a 20-byte Diameter header to the packet; accepts `PROXIABLE` on either type and rejects `ERROR` on a request and `RETRANSMITED` on an answer at configure time |
| `DiameterDecap` | 1/1 | — | Strips the 20-byte header; validates the message first |
| `DiameterPushAVP` | 1/1 | `CODE` (required); `VENDORSPEC`, `VENDOR`; one of `OCTETSTRING`, `UINT32`, `RANDUINT32`, `RANDALPHANUMSTRING N`, `RANDNUMSTRING N`, `RANDALPHASTRING N`, `RANDHEXSTRING N` | Appends an AVP and updates the message Length; validates the message first |
| `DiameterPopAVP` | 1/1 | — | Removes the last AVP and updates the message Length; validates the message first |
| `DiameterPopStorePushAVP` | 1/2 | — | Pops the last AVP from one packet (output 0) and pushes that value back onto the next (output 1); validates the message first |
| `DiameterFlipRequest` | 1/1 | — | Toggles the request bit, turning a request into an answer and back; P is kept in both directions, T is cleared when it produces an answer and E when it produces a request |
| `DiameterAvpEncap` | 1/1 | `CODE` (required); `VENDORID`, `MANDATORY` | Prepends an AVP header (8 bytes, or 12 with `VENDORID`) and pads the AVP to a 4-octet boundary |
| `DiameterAvpDecap` | 1/1 | — | Strips one AVP: consumes the AVP whole when octets follow it, otherwise forwards its value (header 8 bytes, or 12 following the V bit; padding dropped either way) |

Documentation
-------------

The pages installed with the package sit in `PREFIX/share/man/man7`, beside
Click's own, and `elements-diameter.7click.gz` lists all nine with a one-line
summary. Each element page carries its synopsis, ports, arguments, and its drop,
flag and padding contract; `DiameterRatedSource` adds its handlers.

When the prefix is on your `MANPATH`, `man` finds them as usual:

```sh
man DiameterEncap
```

When it is not, point `man` at the prefix explicitly:

```sh
man -M "$HOME/click/share/man" DiameterEncap
man -M "$HOME/click/share/man" elements-diameter
```

Tests
-----

```sh
bats --tap tests                              # click from PATH
CLICK=$HOME/click/bin/click bats --tap tests   # this package installed there
```

`tests/smoke.bats` runs each config under `tests/configs/` and asserts its exact
output. The `malformed-*` configs assert the drop path instead — exit 0, one
warning naming the element and reason, and no `Print` line. The two rejected
`DiameterEncap` flag configs assert a configure failure: non-zero exit, the
argument named in the error, and no `Print` line. `tests/manpages.bats` reads
the prefix the Click binary lives in and asserts one page per element, with its
arguments, handlers and the package element list, whose entries sit under a
known category with a summary; it also checks that the six readers document
their drop path and the two pop elements their no-AVP no-op.
`tests/identity.bats` needs no Click at all: it reads `configure.ac` and `src/`,
requiring the package to identify itself as `click-diameter` 2.1, every include
guard to match its filename, no `<iostream>` include, and no `simple_action`
beside a `push` override (F-14, F-15). CI runs the same command on every pull
request plus a monthly check against upstream Click master.

Malformed input is dropped, never forwarded. The six elements that read a
received frame — `DiameterDecap`, `DiameterAvpDecap`, `DiameterFlipRequest`,
`DiameterPushAVP`, `DiameterPopAVP` and `DiameterPopStorePushAVP` — validate it
first and drop it with one `ELEMENT: dropping malformed packet: REASON` line per
packet: the five that read a message check its Length and flags, and
`DiameterAvpDecap` checks the AVP framing it is handed. Drops are not throttled:
a hostile source can flood the log, and that is accepted.

AVPs are padded to a 4-octet boundary with zero octets, and the AVP Length
counts only the header and the value (RFC 6733 §4.1). `DiameterAvpEncap` adds
that padding and `DiameterAvpDecap` derives it from Length and strips it, so a
message built from the encoder's output passes the message readers and a
sequence of AVPs stays aligned. A standalone AVP that arrives without its
padding still decodes to its value rather than being dropped.

Flag policy
-----------

RFC 6733 §3 forbids E in a request and T in an answer, and §6.2 sets an
answer's P to the same value as the request's. The package builds and reads
headers that way.

`DiameterRatedSource` sets none of the three bits, so a generated request
carries R alone and a generated answer none. `DiameterEncap` starts from a
header whose flags are all clear, sets only the flags the caller asks for, and
rejects `ERROR` on a request and `RETRANSMITED` on an answer at configure time
with an error naming the argument; `PROXIABLE` is accepted on either type,
because the element has no request to consult. `DiameterFlipRequest` clears R
and T together when it turns a request into an answer, and sets R and clears E
when it turns an answer into a request, keeping P in both directions.

Every element that reads a message validates the flags alongside its Length
check, so a received frame carrying E on a request or T on an answer is dropped
with one warning naming the flag. The flip is the one reader that also rewrites
flags: it validates at the door, so a T-bearing answer is dropped rather than
repaired into a request, while an E-bearing answer is legal input and has its E
cleared on the way out. P on either type, E on an answer and T on a request are
not errors, so the readers that only validate forward them unchanged. T on a
request is never rejected: §3 allows it only as a retransmission marker, and a
stateless element cannot judge that.

Randomness
----------

`DiameterRatedSource`, `DiameterEncap` and `DiameterPushAVP` draw every random
field from Click's RNG through `click_random()`: the `hbh`/`e2e` identifiers of
a generated header and the `RAND*` values of `DiameterPushAVP`. None of them
seeds the generator. `RandomSeed(SEED n)` replaces Click's per-router random
seed:

```click
RandomSeed(SEED 12345);
```

The seed is process-global, so it also pins every other element drawing from
`click_random()`, and its position in the configuration does not matter because
the elements draw only at run time. Two runs of the same config then emit the
same octets. The stream advances on every draw, so successive packets still
differ; without a seed the values come from Click's own seed and vary from run
to run. Reproduction assumes a single thread or a fixed draw order: a
multi-threaded router's interleaving is not fixed by the seed.

Known limitations
-----------------

One finding remains open, and it lands outside this repository: the Click fork
`BabisK/click` still carries `conf/test.click`, which does not configure, and
`etc/diameter/`, a stale in-tree copy of these elements (F-16). The removal
is one commit in that fork — delete `conf/test.click` and `etc/diameter/`
there — so nothing in this package can perform or verify it. The package
identity (F-14) and the stale include guards, the `<iostream>` includes in
data-path elements and the dead `simple_action()` beside `push()` (F-15) are
fixed, and `tests/identity.bats` pins them. The file-and-line evidence for all
three stays in `_bmad-output/specs/spec-diameter-package-hardening/findings.md`.

Layout
------

    configure.ac, Makefile.in   build entry points (autoconf, configure, make run here)
    src/                        element sources: one .cc/.hh pair per element, plus diameter.hh
    tests/                      smoke configs, byte-level, man page and identity assertions

License
-------

This package is distributed under the Click license, the same terms as the
[Click modular router](https://github.com/kohler/click): an MIT license plus a
clause forbidding use of the copyright holders' names in advertising or
publicity without prior written permission. The binding text is in
[LICENSE](LICENSE). Copyright (c) 2014 Intracom Telecom and (c) 2026
Charalampos Kaidos.
