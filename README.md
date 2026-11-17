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
upper case). At most one value source -- `OCTETSTRING` or one of these --
supplies the value: supplying two of them fails configuration with an error
naming both, while supplying none appends the header-only AVP. A zero generator
count and `RANDUINT32 false` are not sources, so either may sit beside the one
real source. A generator count above 16,777,184 (16,777,180 with the vendor
header) cannot fit the three-octet message Length, so it fails configuration. A
keyword repeated in one configuration also fails configuration, naming the
argument, instead of silently keeping the last value.

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
| `DiameterRatedSource` | 0/1 | `CODE`, `REQUEST` (required); `RATE` (pps, default 10), `LIMIT`, `ACTIVE`, `APPID`, `STOP` | Emits bare 20-byte messages at a token-bucket rate; hop-by-hop and end-to-end identifiers are seeded once from `click_random()` and counter-advanced per emitted message, so each is unique for the first 2^32 messages of a run; it never sets E, P or T, so a generated request carries R alone and a generated answer none; rejects a `CODE` above `0xFFFFFF` at configure time |
| `DiameterEncap` | 1/1 | `CODE`, `REQUEST` (required); `ERROR`, `PROXIABLE`, `RETRANSMITED`, `APPID` | Prepends a 20-byte Diameter header to the packet and zero-pads the payload to a 4-octet boundary, counting the pad in the Length; hop-by-hop and end-to-end identifiers are seeded once from `click_random()` and counter-advanced per emitted message, so each is unique for the first 2^32 messages of a run; accepts `PROXIABLE` on either type, rejects `ERROR` on a request and `RETRANSMITED` on an answer, rejects a `CODE` above `0xFFFFFF`, and drops a payload whose message Length would exceed `0xFFFFFF` at run time |
| `DiameterDecap` | 1/1 | — | Strips the 20-byte header; validates the message first |
| `DiameterPushAVP` | 1/1 | `CODE` (required); `VENDORSPEC`, `VENDOR`, `MANDATORY`; one of `OCTETSTRING`, `UINT32`, `RANDUINT32`, `RANDALPHANUMSTRING N`, `RANDNUMSTRING N`, `RANDALPHASTRING N`, `RANDHEXSTRING N` | Appends an AVP and updates the message Length; `MANDATORY` sets the AVP's M bit; two value sources or a repeated keyword are refused at configure time; validates the message first and drops a packet whose appended AVP would push the message Length past `0xFFFFFF`, with its own warning |
| `DiameterPopAVP` | 1/1 | — | Removes the last AVP and updates the message Length; validates the message first |
| `DiameterPopStorePushAVP` | 1/2 | — | Pops the last AVP from one packet (output 0) and pushes that value back onto the next (output 1); validates the message first and drops a push that would exceed `0xFFFFFF`, keeping the stored AVP |
| `DiameterFlipRequest` | 1/1 | — | Toggles the request bit, turning a request into an answer and back; P is kept in both directions, T is cleared when it produces an answer and E when it produces a request |
| `DiameterAvpEncap` | 1/1 | `CODE` (required); `VENDORID`, `MANDATORY` | Prepends an AVP header (8 bytes, or 12 with `VENDORID`) and pads the AVP to a 4-octet boundary; drops a value whose AVP Length would exceed `0xFFFFFF` |
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
warning naming the element and reason, and no `Print` line — while
`push-avp-length-overflow.click`, `encap-length-overflow.click`,
`popstorepush-length-overflow.click` and `avp-encap-length-overflow.click` assert
the other drop shape: a well-formed frame whose three-octet Length field cannot
hold the result is dropped rather than wrapped, with a warning naming the field.
Nineteen configs assert a configure failure: the two `DiameterEncap` flag pairs,
the two `VENDORSPEC` and `VENDOR` refusals, six `DiameterPushAVP` value-source
conflicts, three repeated-keyword configs, two generator-cap configs, and the
CODE-range configs in both writers. Each expects a non-zero exit, the named
argument in the error, and no `Print` line. `tests/manpages.bats` reads
the prefix the Click binary lives in and asserts one page per element, with its
arguments, handlers and the package element list, whose entries sit under a
known category with a summary; it also checks that the six readers document
their drop path and the two pop elements their no-AVP no-op.
`tests/identity.bats` needs no Click at all: it reads `configure.ac` and `src/`,
requiring `AC_INIT` to name the tarball `click-diameter` 2.1 (the Click package
name stays `diameter`), every include guard to match its filename, no
`<iostream>` include, and no `simple_action` beside a `push` override (F-14,
F-15). It runs on its own with `bats tests/identity.bats`. CI runs the same
command on every pull request and every push to `master`, plus a monthly check
against the latest Click master.

Malformed input is dropped, never forwarded. The six elements that read a
received frame — `DiameterDecap`, `DiameterAvpDecap`, `DiameterFlipRequest`,
`DiameterPushAVP`, `DiameterPopAVP` and `DiameterPopStorePushAVP` — validate it
first and drop it with one `ELEMENT: dropping malformed packet: REASON` line per
packet: the five that read a message check its Version, its Length — which must
be a multiple of 4 as well as equal to the packet — and its flags, and
`DiameterAvpDecap` checks the AVP framing it is handed. Drops are not throttled:
a hostile source can flood the log, and that is accepted.

AVPs are padded to a 4-octet boundary with zero octets, and the AVP Length
counts only the header and the value (RFC 6733 §4.1). `DiameterAvpEncap` adds
that padding and `DiameterAvpDecap` derives it from Length and strips it, so a
message built from the encoder's output passes the message readers and a
sequence of AVPs stays aligned. A standalone AVP that arrives without its
padding still decodes to its value rather than being dropped.

Messages are padded the same way. RFC 6733 §3 defines the Message Length as
covering the header and the padded AVPs, so it is always a multiple of 4;
`DiameterEncap` zero-pads its payload to that boundary and counts the pad in the
Length, and `DiameterDecap` forwards the pad with the payload because the pad is
part of the message. A payload already on the boundary gains no octet. Padding
repairs the header rule only: a payload that is not already a sequence of padded
AVPs does not become walkable, and an AVP reader drops it
(`encap-padding-push-avp` pins the drop). A
received Length that is not a multiple of 4 is rejected by every message
reader with `the Length field is not a multiple of 4`.

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

Every element that reads a message validates the flags alongside its Version
and Length checks, so a received frame carrying a Version other than 1, E on a
request or T on an answer is dropped with one warning naming the fault. The flip
is the one reader that also rewrites flags: it validates at the door, so a
T-bearing answer is dropped rather than repaired into a request, while an
E-bearing answer is legal input and has its E cleared on the way out. P on
either type, E on an answer and T on a request are not errors, so the readers
that only validate forward them unchanged. T on a request is never rejected: §3
allows it only as a retransmission marker, and a stateless element cannot judge
that.

Randomness
----------

Two kinds of random input reach these elements. `DiameterRatedSource` and
`DiameterEncap` seed one counter per identifier, the `hbh` and `e2e` fields,
once from `click_random()` when the element is initialized, then advance each
counter by one for every message the element emits; `DiameterPushAVP` draws each
`RAND*` value from `click_random()` per appended AVP. None of them seeds the
generator. `RandomSeed(SEED n)` replaces Click's per-router random seed:

```click
RandomSeed(SEED 12345);
```

The seed is process-global, so it also pins every other element drawing from
`click_random()`, and its position in the configuration does not matter because
every element draws only after all elements are configured. Two runs of the same
config then emit the same octets. The identifiers are counters rather than
draws: each field is unique for the first 2^32 messages of a run, so a repeated
hop-by-hop or end-to-end value means a wrap, not the birthday collision a 32-bit
draw reaches in a few hundred thousand messages, and the counters are atomic, so
two router threads never share a value. The end-to-end field is a 32-bit counter
presented with a twelve/twenty split: its high-order 12 bits advance when the
low-order 20 bits wrap. RFC 6733 §3 only permits a reboot-time value in the high
half and a random value in the low half; this package reads neither and the seed
chooses both starting values, which is what keeps the run reproducible. A new
run starts a new sequence from its seed; nothing is claimed across reboots. A
seeded writer now consumes two draws at initialization instead of two per
message, so a configuration that pairs it with a `RAND*` generator moves that
generator's values from the second message on; `randomness-encap-push-avp` pins
the new stream position. The `RAND*` generators consume the stream on every
draw, so successive values differ; without a seed every value comes from Click's
own seed and varies from run to run. Reproduction assumes a
single thread or a fixed order for the `RAND*` draws: a multi-threaded router's
interleaving is not fixed by the seed, although the counters still hand out
distinct values.

Known limitations
-----------------

One finding remains open, and it lands outside this repository: the Click fork
`BabisK/click` still carries `conf/test.click`, which does not configure, and
`etc/diameter/`, a stale in-tree copy of these elements (F-16; `findings.md`
records the fork under its former name, `babisk/diameter`). The removal is one
commit in that fork — delete `conf/test.click` and `etc/diameter/` there — so
nothing in this package can perform or verify it. The package identity (F-14)
and the stale include guards, the `<iostream>` includes in data-path elements
and the dead `simple_action()` beside `push()` (F-15) are fixed, and
`tests/identity.bats` pins them. The symptom evidence for all three stays in
`_bmad-output/specs/spec-diameter-package-hardening/findings.md`.

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
