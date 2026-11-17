# tests

Click configs that exercise the package, with byte-level assertions, plus
assertions over the man pages the install renders and over the source tree
itself. There is no `make check`; these run against an installed Click that
already carries `diameter.uo`, except the source-level `identity.bats`, which
needs no Click at all.

## Running

Requires [bats-core](https://github.com/bats-core/bats-core) 1.5 or newer — the
seeded tests use `BATS_TEST_TMPDIR` — and a Click that carries the `RandomSeed`
test element, which the `randomness-*` and `identifiers-*` configs load. On the
CI image bats comes from `apt-get install -y bats`.

```sh
bats --tap tests                              # click from PATH
CLICK=~/click/bin/click bats --tap tests      # explicit binary
CLICK=~/click/bin/click bats --tap --filter pop-avp tests   # one config
bats --tap tests/identity.bats                # source checks, no Click needed
```

`smoke.bats` runs every config under `configs/` with a 10 s timeout, then
asserts the bytes the config printed: label, packet length and hex contents. A
wrong length field, a changed flag or an off-by-one is a failed test, not a
silent pass. A config that sets no seed varies its `hbh`/`e2e` identifiers per
run, so the test matches them with a regex instead of pinning them, and the
`encap` test runs its config a second time to check that every other field comes
back byte for byte.

`manpages.bats` reads the pages `make install` rendered into the same installed
prefix. It resolves the prefix from the Click binary — `$CLICK`, or `click` on
`PATH`, through `readlink -f` and two `dirname`s — and then walks
`PREFIX/share/man/man7`: nine `Diameter*.7click.gz` element pages must exist,
beside `elements-diameter.7click.gz`. Every page must name its element, carry
the generated `Ports`, `Processing` and `Package: diameter` lines, have a
non-empty DESCRIPTION and name each argument its header parses in both the
SYNOPSIS and the DESCRIPTION; `DiameterRatedSource` must list its five handlers,
and the element list must file all nine under one of the three known categories
— `Basic Sources and Sinks`, `Basic Packet Transfer`, `Basic Packet
Modification` — each with a non-empty summary line. The drop path of the six
readers and the no-AVP no-op of the two pop elements are asserted too. The
pages come from the `=c`/`=d` blocks in `src/`, so a header with no block, or
one whose block no longer names an argument the header parses, fails the run;
an argument added to a `configure()` that the page does not mention is caught
at review instead. When the prefix is not on `MANPATH`, read a page with
`man -M PREFIX/share/man DiameterEncap`.

`identity.bats` reads the tree instead of a running router: `configure.ac`, and
every header and source under `src/`. It copies `configure.ac` into a temporary
directory, runs `autoconf` there, and requires `./configure --version` to print
`click-diameter configure 2.1` (F-14); requires every `src/*.hh` include guard to
be `<UPPERCASE STEM>_HH_` with an `#endif` comment naming the same guard;
requires no file under `src/` to include `<iostream>`, a userlevel-only header
the data-path sources carried; and requires no header to declare `simple_action`
beside `push`, where Click's `Element::push` would never call it (F-15). A byte
assertion cannot see any of these: a stale guard, an unused include and a
shadowed hook all leave the emitted packets identical, so only a scan of the
tree catches a regression. Autoconf 2.72 warns about `AC_OUTPUT` on
`configure.ac:73`; that warning is pre-existing, and the test reads stdout only.

The `randomness-*` configs pin `RandomSeed(SEED 12345)`, and their assertions
live in `expect_seeded`, the seeded counterpart of `expect_drop` and
`expect_configure_failure`: each config runs once, then with the seed rewritten
in a copy, then again more than a second later, and requires the two packets of
a run to differ, the two seeds to differ, and the rerun to reproduce the first
run byte for byte. A stream seeded from the wall clock, frozen after one draw or
ignoring the seed fails that. Seven configs cover every seeded path changed by
F-11: `randomness-encap` and `randomness-rated-source` for the identifiers,
`randomness-rated-source-pull` for the pull path, `randomness-push-avp` for the
generated string, `randomness-push-avp-uint32` for `RANDUINT32`,
`randomness-encap-push-avp` for the stream position a seeded writer leaves for a
downstream `RAND*` consumer, and `identifiers-rated-source-pull-unique` for the
refused pulls between the frames the pull path returns. The two writer elements
no longer draw an identifier per message: each seeds both counters once from
`click_random()` in `initialize()` and advances them by one per emitted message,
so each field is unique for the first 2^32 messages of a run. The `identifiers-*`
configs prove that at the length where a 32-bit draw repeats:
`identifiers-encap-unique` sends 240 000 messages through `DiameterEncap` from
`InfiniteSource`, and
`identifiers-rated-source-unique` sends the same count at `RATE 1000` through
`DiameterRatedSource`. All run under `click --simtime`, so four minutes of the
story's rate takes under a second; `expect_identifier_run` requires the printed
frame count, the distinct count of each field, a string comparison that finds no
frame whose two identifiers are equal, and a sequence that steps by exactly one
value per message, so a gap or a reset fails; `expect_unique_identifiers` adds a
byte-identical second run. A per-packet draw fails the distinct counts with the
baseline's 11/7 and 17/13 duplicate values; the baseline's 37/30 "equal pairs"
were an artifact of comparing hex fields numerically and are 0/0 as strings. A
counter that steps on a refused token still yields distinct values but fails the
consecutive span. `identifiers-encap-wrap` crosses the 2^20 end-to-end carry in
one 1 048 577-message run, so a low half that wraps without carrying fails the
same checks. `identifiers-encap-drop-then-emit` sends one payload the writer
refuses and then one it emits through the same element, and requires the emitted
frame to carry the seed's first pair, so a counter advanced before the drop
fails. The
`randomness-source` test is not a config: it greps `src/` and fails on any
`srand`, `rand`, `srandom`, `random`, `click_srandom` or
`click_random_srandom` call, so a reintroduced reseed fails even though no byte
assertion can see `configure()`.

The `rand-*` tests pin the length and the alphabet of each `DiameterPushAVP`
generator; one of them appends 10 kB to the packet, so Click prints its
`expensive Packet::put` advisory beside the `Print` line.

The five `smp-*` tests are the only ones that run under `click -j 2`.
Multithreading is a Click build option, so they need a Click configured with
`--enable-user-multithread`; a plain build prints `warning: Click was built
without multithread support, running single threaded` and `-j 2` silently
degrades. Each test therefore checks the run's exit status, then skips with a
reason on that warning, and then fails if the run reports a rejected `thread
preference` — because a config whose `StaticThreadSched` line did not take
effect runs single threaded and would quietly turn these tests back into shape
checks. `StaticThreadSched` is load-bearing: delete it and the pre-change
package passes the two discriminating tests again.

To run them locally, build a second Click and this package against it:

```bash
git -C ../click archive 9197a594b | tar -x -C ../click-mt-src
cd ../click-mt-src && ./configure --prefix="$HOME/click-mt" --disable-linuxmodule \
  --enable-user-multithread && make -j8 && make install
cd <package> && ./configure --with-click="$HOME/click-mt" --prefix="$HOME/click-mt" \
  && make && make install
CLICK="$HOME/click-mt/bin/click" bats --tap --filter 'smp-' tests
```

CI builds its Click with that flag, so the gate runs all five. Without it a
local run reports a skip, and the two-thread evidence comes from a run like the
one above or from the ThreadSanitizer check below.

What each one proves, and what it does not:

- `smp-encap` and `smp-avpencap` prove that `DiameterEncap` and
  `DiameterAvpEncap` derive their Length from the packet in hand. Their two
  producers send a 4- and an 8-octet payload, so the header Length and the AVP
  Length differ per frame; a write into a shared member between `setLength` and
  `encode` makes one frame carry the other packet's Length, and the test fails
  on it. The per-run frame count is high on purpose: on the build before this
  fix the same configs produced 20 to 37 mismatched frames in roughly 9500, so a
  short run could pass by luck. Only the first source stops the run, so the
  second keeps pushing until then.
- `smp-push-avp` is a shape and regression check, not a race detector:
  `DiameterPushAVP` takes its AVP Length from configuration, so every frame it
  appends has the same Length no matter which thread wins. Its two sources carry
  different Command Codes, so the output shows that both threads pushed, but a
  verdict on that element's shared state needs ThreadSanitizer.
- `smp-popstorepush` is a shape and no-crash check over the one shared store:
  every input yields exactly one output frame, the 32-octet remainder of an
  unarmed packet or the 56-octet message of an armed one, so a frame whose
  Length or AVP Length disagrees with its octets fails the run, as does the
  crash the pre-change package produces when two threads rewrite the member
  header and the store at once. Marker mixing is legal here: the store is shared
  by both threads, so an output-1 frame can pair one producer's packet with the
  other's stored AVP, and a perfect alternation can leave one producer only on
  the armed slot, so the test requires both producers' hop-by-hop and end-to-end
  pairs somewhere in the output rather than on each output. A verdict on the
  store itself needs ThreadSanitizer.
- `smp-popstorepush-loop` proves the pairing rule across threads: the pop runs on
  thread 0, the 32-octet remainder crosses a `Queue`, and a `DelayUnqueue` bound
  to thread 1 pushes it back into the element, which must still hold the AVP
  popped on thread 0 and emit the restored 44-octet message on output 1. A
  per-thread store would pop the remainder again and print a second 20-octet
  output-0 frame, so the two pinned frames fail it. It carries one packet, so it
  proves nothing about contention or header corruption; `smp-popstorepush` and
  ThreadSanitizer cover that.

None of the five can see a race in the shared `String` that holds `DiameterPushAVP`'s value:
a corrupted value is still hex, so any regex over the printed octets accepts it.
ThreadSanitizer is what proves that part, and it is the reproducible negative
control for these elements: on the pre-change package it reports races rooted at
`diameterpushavp.cc`'s `datastring` assignment and at
`diameterpopstorepushavp.cc`'s store, and aborts, while a fixed package reports
no racing access inside this package at all.

`tests/tsan-check.sh CLICK CONFIG...` runs that check. CI runs it in the
`thread-sanitizer` job against a Click and a package built with
`-fsanitize=thread`, so no edge case here depends on someone remembering a
manual step. The script sets `TSAN_OPTIONS=exitcode=0`, so a clean package exits
0 even though TSan reports Click's own shutdown races; a non-zero status then
means a crash or a configuration failure, while the race verdict comes only from
reports whose racing access (`#0` frame) is in `src/diameter.*`. It also fails if
the installed module does not link `libtsan`, which is the trap a plain
`make install` into a sanitizer prefix leaves.

The script ignores a report only when its racing `#0` access is in Click's
`click/sync.hh` or `click/atomic.hh` and the same report's stack names
`Spinlock::`; every other report is judged on its package frames as before. The
lock is an inline-assembly `xchg` loop, which ThreadSanitizer cannot see, so the
lock's `_lock`, `_owner` and `_depth` accesses are reported as races even though
the `xchg` orders them, and those frames are Click core, not package state. An
element that holds a `Spinlock` therefore announces its critical section with
`__tsan_acquire`/`__tsan_release` (a no-op in a non-sanitizer build), so a race
on the data the lock protects is still reported on the element's own line and
still fails the check. `DiameterPopStorePushAVP` is the only element that takes
that lock.

To reproduce locally, build the pair the way the job does:

```bash
env CXXFLAGS="-fsanitize=thread -g -O1" LDFLAGS="-fsanitize=thread" \
  ./configure --prefix="$HOME/click-tsan" --disable-linuxmodule --enable-user-multithread
env CXXFLAGS="-fsanitize=thread -g -O1" LDFLAGS="-fsanitize=thread" make -j8 && make install
# then, from the package:
./configure --with-click="$HOME/click-tsan" --prefix="$HOME/click-tsan"
make CXXFLAGS="-fsanitize=thread -g -O1 -Wall -Wextra -fPIC -shared"
make install CXXFLAGS="-fsanitize=thread -g -O1 -Wall -Wextra -fPIC -shared"
tests/tsan-check.sh "$HOME/click-tsan/bin/click" tests/configs/smp-*.click
```

The `malformed-*` configs assert the drop path instead: exit 0, no `Print`
line, and exactly one warning naming the element and reason.

`push-avp-length-overflow.click` asserts the one drop that is not a malformed
frame: the message passes validation, but appending the AVP would push its
Length past the three-octet field (RFC 6733 §3), so `DiameterPushAVP` drops it
with `DiameterPushAVP: dropping packet: appending the AVP would exceed the
three-octet Length field (RFC 6733 section 3)` and forwards nothing. The guard
runs before `put()`, so the output is that one line and no Put advisory. Its
counterpart `push-avp-length-max.click` is one 4-octet step shorter and appends
16,777,212 octets, so the pair pins both sides of the ceiling.

Malformed input is dropped, never forwarded. A drop is asserted with
`expect_drop`, which requires exit 0, exactly one warning of the form
`ELEMENT: dropping malformed packet: REASON`, and no `Print` line; a forwarded
malformed packet or a silent drop fails the run. Drops are not throttled, so
a hostile source can flood the log; that is accepted.

Received messages are validated for framing and flags: RFC 6733 §3 fixes the
Version at 1, so a message whose first octet is not 1 is dropped with
`the Version field is not 1` before its Length is compared; an AVP has no
Version field, so `DiameterAvpDecap` is exempt. Section 3 also makes the Message
Length a multiple of 4, so a frame whose Length is not a multiple of 4 is
dropped with `the Length field is not a multiple of 4`; that test runs after the
Version and short-header checks and before the packet-length comparison, so the
Version and truncation reasons still outrank it and it outranks a Length
mismatch. Section 3
also forbids E in a request and T in an answer, so a frame with either is
dropped with `the E bit is set on a request` or `the T bit is set on an answer`.
P is legal on either message type, so it never causes a drop. The same walk
rejects a vendor AVP whose `V` bit is set with a zero Vendor-Id, per RFC 6733
§4.1.1, and drops it with `the V bit is set with a zero Vendor-Id`; every AVP
walker inherits that check, and the Length checks keep precedence over it.

The whole message is validated, not only its header: `DiameterDecap` and
`DiameterFlipRequest` walk the body too, so a message carrying a malformed AVP
or a forbidden `V=1, Vendor-Id=0` AVP is dropped by the reader instead of being
forwarded or re-emitted with the defect intact. The body of every decapped
message must therefore be a sequence of AVPs; `decap.click`,
`decap-p-on-answer.click`, `decap-t-on-request.click` and `encap-decap.click` use
one 8-octet AVP for it.

A message is the header plus a sequence of padded AVPs, so its Length is a
multiple of 4; `DiameterEncap` requires a body already on that boundary.
`encap-unaligned-payload.click` pins the refusal: a 5-octet payload is dropped
with `the payload length is not a multiple of 4, so it cannot be a sequence of
padded AVPs` rather than zero-padded into a frame that only looks like a
message. `encap-body-not-avps.click` pins the remaining limit: a 4-octet body is
aligned, so the writer forwards it, but `DiameterPushAVP` drops it because it is
not an AVP. `encap`, `encap-empty`, `encap-decap`, `encap-push-pop` and
`smp-encap` keep their existing bytes.

A configuration the package refuses is asserted with `expect_configure_failure`,
which takes the config, the refusing element and the named message; it requires a
non-zero exit, Click's whole configure-failure output for that config (path and
line, the `While configuring 'ELEMENT@N :: ELEMENT':` line, the named error, and
`Router could not be initialized!`), and no `Print` line. The element is a
parameter because more than one element refuses a configuration, and the `@N`
suffix is matched with a wildcard rather than pinned. Twenty-one configs take that
path: `encap-error-on-request.click`, `encap-retransmit-on-answer.click`,
`encap-code-too-large.click`, `encap-code-first-too-large.click`,
`rated-source-code-too-large.click`,
`rated-source-code-first-too-large.click`,
`push-avp-vendor-missing.click`, `push-avp-vendor-zero.click`,
`push-avp-conflict-octetstring-uint32.click`,
`push-avp-conflict-randnumstring-randhexstring.click`,
`push-avp-conflict-empty-octetstring-uint32.click`,
`push-avp-conflict-octetstring-randuint32.click`,
`push-avp-conflict-randalphanumstring-randalphastring.click`,
`push-avp-conflict-three.click`, `encap-duplicate-code.click`,
`rated-source-duplicate-rate.click`, `push-avp-duplicate-octetstring.click`,
`push-avp-duplicate-wrapped.click`, `avp-encap-duplicate-code.click`,
`push-avp-randhex-too-large.click` and
`push-avp-randhex-too-large-vendor.click`. The four CODE-range configs refuse a
`CODE` above `0xFFFFFF` in the two writers -- both the `0x01000118` repro value
and the first illegal value `0x1000000` -- because RFC 6733 §3 sizes the
Command Code at three octets, so `0x01000118` would silently go out as
`0x000118`. The six conflict configs refuse more than one
value source in one `DiameterPushAVP`, which accepts at most one, and the
three-source one also pins that the error names the first conflicting pair in
documented argument order. The five duplicate-keyword configs refuse a keyword
given twice, naming it, in `DiameterEncap`'s keyword-only shape,
`DiameterRatedSource`'s positional-plus-keyword shape, `DiameterPushAVP`,
`DiameterAvpEncap`, and `DiameterPushAVP` with the keyword and its value split
across a line, which Click still parses as one argument.
The two generator-cap configs refuse a `RANDHEXSTRING` count one past the
16,777,184-octet body limit (16,777,180 with the vendor header), so the value
is never materialised.
`push-avp-rand-zero.click` and `push-avp-randuint32-false.click` pin the other
side of the one-source rule: a zero generator count and a false `RANDUINT32`
supply nothing, so each configuration prints bytes. Every other `encap-*`,
`rated-source*` and `push-avp*` config configures and prints bytes or the one
drop line its own row names.

CI runs the same command on every pull request and every push to `master`, plus
monthly against the latest Click master, so a local pass over the same Click is
the same check. CI's Click is built with `--enable-user-multithread`, so the
five `smp-*` tests run there rather than skipping; the `thread-sanitizer` job
runs the same script against a sanitizer build, so a local run only reproduces a
failure.

## configs/

Behavior that must keep working. Each config has one test in `smoke.bats`:

| Config | Covers |
|---|---|
| `push-avp.click` | appending an AVP, header length updated |
| `push-avp-vendor.click` | a vendor AVP carries V, AVP Length 15 and Vendor-Id 42: 36 octets in total (RFC 6733 §4.1.1) |
| `push-avp-vendor-missing.click` | `VENDORSPEC true` without `VENDOR` rejected at configure time (A-1, RFC 6733 §4.1.1) |
| `push-avp-vendor-zero.click` | `VENDORSPEC true, VENDOR 0` rejected at configure time (RFC 6733 §4.1.1) |
| `push-avp-conflict-octetstring-uint32.click` | `OCTETSTRING` and `UINT32` together rejected at configure time, naming both arguments (A-10, CAP-1) |
| `push-avp-conflict-randnumstring-randhexstring.click` | two `RAND*STRING` generators rejected at configure time rather than the first silently winning (A-10) |
| `push-avp-conflict-empty-octetstring-uint32.click` | `OCTETSTRING ""` is a supplied source, so it conflicts with `UINT32 0` and both are named (A-10) |
| `push-avp-conflict-octetstring-randuint32.click` | `RANDUINT32 true` is a supplied source, so it conflicts with `OCTETSTRING` and both are named (A-10) |
| `push-avp-conflict-randalphanumstring-randalphastring.click` | two `RAND*STRING` generators rejected at configure time, naming both (A-10) |
| `push-avp-conflict-three.click` | three supplied sources rejected naming the first conflicting pair in documented argument order (A-10) |
| `push-avp-vendor-unused.click` | `VENDOR 42` without `VENDORSPEC` is ignored: the AVP keeps the 8-octet non-vendor header |
| `push-avp-mandatory.click` | `MANDATORY true` sets the M bit: AVP flags `40` rather than `00` (A-2, RFC 6733 §4.1) |
| `push-avp-mandatory-vendor.click` | `MANDATORY true, VENDORSPEC true, VENDOR 42` sets M and V in separate bits: AVP flags `c0` |
| `push-avp-mandatory-false.click` | `MANDATORY false` leaves the M bit clear: byte-identical to `push-avp.click` |
| `push-avp-uint32-zero.click` | `UINT32 0` is a four-octet zero at AVP Length 12: 32 octets, not a header-only AVP (A-3, RFC 6733 §4.2) |
| `push-avp-uint32-zero-vendor.click` | `UINT32 0` after the 12-octet vendor header is AVP Length 16: 36 octets (A-3, RFC 6733 §4.2) |
| `push-avp-empty.click` | an empty `OCTETSTRING` keeps the 8-octet header-only AVP, the case that must not move (A-3, RFC 6733 §4.2) |
| `push-avp-empty-vendor.click` | the same empty value after the 12-octet vendor header: AVP Length 12, 32 octets (A-3, RFC 6733 §4.2) |
| `push-avp-no-value.click` | no value source at all (including a lone zero generator count or `RANDUINT32 false`): AVP Length 8, 28 octets (A-3, RFC 6733 §4.2) |
| `push-avp-uint32.click` | `UINT32 2001` is the four-octet big-endian value `000007d1`: AVP Length 12, 32 octets |
| `push-avp-randuint32-false.click` | `RANDUINT32 false` supplies nothing, so `OCTETSTRING` is the single source: byte-identical to `push-avp.click` (A-10) |
| `push-avp-randuint32-zero.click` | `RandomSeed(SEED 808357014)` makes Click's first draw zero: `RANDUINT32` is four zero octets at AVP Length 12 |
| `push-avp-rand-zero.click` | `RANDNUMSTRING 0` is unused, not a second source: `RANDHEXSTRING 4` supplies four hex characters at AVP Length 12 (A-10) |
| `push-avp-duplicate-octetstring.click` | a repeated `OCTETSTRING` fails configuration naming the argument instead of keeping the last value (DW-2) |
| `push-avp-duplicate-wrapped.click` | a repeated `MANDATORY` with its value split across a line still fails configuration: Click treats the newline as whitespace (DW-2) |
| `avp-encap-duplicate-code.click` | the fourth configurable element refuses a repeated `CODE` naming the argument (DW-2) |
| `encap-duplicate-code.click` | a repeated `CODE` fails configuration naming the argument (DW-2) |
| `rated-source-duplicate-rate.click` | a repeated `RATE` after the positional shape fails configuration naming the argument (DW-2) |
| `push-avp-randhex-too-large.click` | `RANDHEXSTRING 16777185` is past the 16,777,184-octet body limit and fails configuration (DW-6) |
| `push-avp-randhex-too-large-vendor.click` | the vendor header lowers the generator limit to 16,777,180, so 16,777,181 fails configuration (DW-6) |
| `push-avp-length-overflow.click` | a maximal 16,777,212-octet message plus an 8-octet AVP is dropped with its own warning instead of wrapping Length (A-9, RFC 6733 §3) |
| `push-avp-length-max.click` | the largest legal message, 16,777,212 octets with message Length `0xfffffc` and AVP Length `0xffffe8`, still appends: the guard is not over-broad (A-9) |
| `push-avp-rand.click` | generated value, 8 characters |
| `rand-alphanum-one.click` | `RANDALPHANUMSTRING 1` emits one character: AVP Length 9 and three zero pad octets (F-8) |
| `rand-hex-one.click` | `RANDHEXSTRING 1` emits one character rather than an empty AVP (F-8) |
| `rand-hex-alphabet.click` | `RANDHEXSTRING 10000` draws all 10,000 characters from `0`-`9`/`A`-`F` (F-9) |
| `rand-num-four.click` | `RANDNUMSTRING 4` emits four digits: AVP Length 12 |
| `rand-alpha-four.click` | `RANDALPHASTRING 4` emits four letters: AVP Length 12 |
| `smp-push-avp.click` | two `DiameterRatedSource` elements on two threads into one `DiameterPushAVP` under `click -j 2`: every frame is one 36-octet append, Length `0x24`, AVP Length `0x10`, and both sources' Command Codes appear (CAP-5 shape check) |
| `smp-encap.click` | two 4- and 8-octet payloads on two threads into one `DiameterEncap`: every frame's Length matches its octets, so a cross-thread write fails the run (CAP-5) |
| `smp-avpencap.click` | the same two payloads on two threads into one `DiameterAvpEncap`: every frame's AVP Length matches its octets (CAP-5) |
| `smp-popstorepush.click` | two 44-octet two-AVP messages on two threads into one `DiameterPopStorePushAVP`: every output-0 frame is the 32-octet remainder, every output-1 frame the 56-octet message with its two AVPs and the stored one, each AVP Length 0x0c against its four value octets, both producers' hop-by-hop and end-to-end pairs appear somewhere in the output, and both outputs are non-empty; the pre-change package crashes on the same config (shape and no-crash check; the shared store makes marker mixing legal, ThreadSanitizer proves the store) |
| `smp-popstorepush-loop.click` | one 44-octet message popped on thread 0, its remainder sent through a `Queue` and returned by a `DelayUnqueue` on thread 1: output 0 prints the 32-octet remainder and output 1 the restored 44-octet message, so a per-thread store (which would print a second 20-octet output-0 frame and never the output-1 frame) fails the pinned bytes |
| `pop-avp.click` | removing the last AVP from a two-AVP message |
| `avp-roundtrip.click` | `DiameterAvpEncap` then `DiameterAvpDecap` returns the payload |
| `avp-padding.click` | a 5-octet value pads to a 16-octet AVP: Length 13, three zero octets |
| `avp-padding-two.click` | a 2-octet value pads to 12 octets with two zero octets |
| `avp-padding-one.click` | a 3-octet value pads to 12 octets with one zero octet |
| `avp-padding-none.click` | a 4-octet value needs no padding: 12 octets |
| `avp-encap-length-overflow.click` | a 16,777,210-octet value would wrap the three-octet AVP Length, so the envelope is dropped with its own warning (DW-5) |
| `avp-encap-length-max.click` | 16,777,207 value octets plus the 8-octet header is exactly `0xFFFFFF`: the largest legal AVP Length still emits, so the guard is `>` not `>=` (DW-5) |
| `avp-encap-length-max-vendor.click` | the same inclusive ceiling with the 12-octet vendor header: 16,777,203 value octets, flags `80`, Length `ffffff`, Vendor-Id 42 (DW-5) |
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
| `decap.click` | stripping the 20-byte header leaves the 8-octet AVP body; the message is validated as a whole |
| `encap.click` | a 4-octet payload gets a version 1 header whose Length counts the header plus the payload, 24 octets (F-4) |
| `encap-empty.click` | a zero-octet packet gets a 20-octet header, version 1 and Length 20 (F-4) |
| `encap-decap.click` | Encap then Decap forwards a valid 8-octet AVP body instead of dropping it (F-4) |
| `encap-unaligned-payload.click` | a 5-octet payload cannot be a sequence of padded AVPs, so the writer drops it with its own warning instead of zero-padding it (CAP-2/A-4, RFC 6733 §3) |
| `encap-body-not-avps.click` | a 4-octet body is aligned but is not an AVP, so `DiameterPushAVP` drops it: alignment is not validity (V-8) |
| `encap-length-overflow.click` | a 16,777,200-octet payload whose message Length would pass `0xFFFFFF` is dropped with its own warning instead of wrapping the Length (DW-4) |
| `encap-push-pop.click` | Encap then PushAVP grows a 28-octet frame to 44 and PopAVP restores 28 (F-4) |
| `encap-error-on-answer.click` | E on an answer is legal and unchecked: flags `20` |
| `encap-retransmit-on-request.click` | T on a request is not checked: flags `90` |
| `encap-proxiable-on-request.click` | P on a request is legal: flags `c0` |
| `encap-proxiable-on-answer.click` | P on an answer is accepted on the caller's declaration, since Encap has no request to mirror: flags `40` |
| `encap-error-on-request.click` | `ERROR true` on a request rejected at configure time (RFC 6733 §3) |
| `encap-retransmit-on-answer.click` | `RETRANSMITED true` on an answer rejected at configure time (RFC 6733 §3) |
| `encap-code-too-large.click` | `CODE 16777496` (`0x01000118`) above the three-octet Command Code field rejected at configure time instead of truncated to `000118` (A-9, RFC 6733 §3) |
| `encap-code-first-too-large.click` | `CODE 16777216` (`0x1000000`), the first value that does not fit three octets, rejected at configure time (A-9, RFC 6733 §3) |
| `encap-code-max.click` | `CODE 16777215` (`0xFFFFFF`) is in range and prints `ffffff`: the ceiling is inclusive (A-9, RFC 6733 §3.1) |
| `rated-source.click` | a generated message is 20 octets: version 1, Length 20, flags `80`, code `000118`, App-Id 42 |
| `rated-source-answer.click` | a generated answer is 20 octets with flags `00`: E, P and T clear |
| `rated-source-code-too-large.click` | the same `CODE 16777496` rejected by `DiameterRatedSource`, the second writer that shares `setCode()` (A-9) |
| `rated-source-code-first-too-large.click` | the first illegal `CODE 16777216` (`0x1000000`) rejected by `DiameterRatedSource` (A-9) |
| `rated-source-code-max.click` | the same inclusive ceiling in a generated 20-octet message: Length 20, code `ffffff` (A-9) |
| `randomness-encap.click` | `RandomSeed(SEED 12345)` with `DiameterEncap`: two 24-octet frames, reproduced across runs, identifiers differ (F-11) |
| `randomness-rated-source.click` | `RandomSeed(SEED 12345)` with `DiameterRatedSource`: two 20-octet frames, reproduced across runs, identifiers differ (F-11) |
| `randomness-push-avp.click` | `RandomSeed(SEED 12345)` with `DiameterPushAVP(RANDHEXSTRING 8)`: two 36-octet frames, reproduced across runs, values differ (F-11) |
| `randomness-push-avp-uint32.click` | `RandomSeed(SEED 12345)` with `DiameterPushAVP(RANDUINT32 true)`: two 32-octet frames, reproduced across runs, values differ (F-11) |
| `randomness-rated-source-pull.click` | `RandomSeed(SEED 12345)` with `Unqueue` forcing `DiameterRatedSource`'s pull path: two 20-octet frames, reproduced across runs, identifiers differ, and the literal first frame is pinned (F-11) |
| `identifiers-rated-source-pull-unique.click` | the pull path at `RATE 10` under `--simtime`: refused pulls between the three returned packets consume no identifier, so the fields stay consecutive |
| `identifiers-encap-unique.click` | `RandomSeed(SEED 12345)` with 240 000 messages through `DiameterEncap` under `--simtime`: every hop-by-hop and end-to-end value distinct and consecutive, no frame with two equal identifiers, reproduced across runs |
| `identifiers-rated-source-unique.click` | the same counts at `RATE 1000` through `DiameterRatedSource` under `--simtime`, so a counter that steps on a refused token leaves a gap in the sequence |
| `identifiers-encap-wrap.click` | 1 048 577 messages through `DiameterEncap` under `--simtime`: crosses the 2^20 end-to-end carry once, and the fields stay distinct and consecutive |
| `identifiers-encap-drop-then-emit.click` | one payload the writer refuses and then one it emits through the same element: the emitted frame carries the seed's first pair, so a drop consumes no identifier |
| `randomness-encap-push-avp.click` | `RandomSeed(SEED 12345)` with `DiameterEncap` chained into `DiameterPushAVP(RANDHEXSTRING 8)`: pins the stream position a seeded writer leaves for a downstream generator |
| `popstorepush-roundtrip.click` | popping an unpadded AVP and pushing it back restores the 44-octet message (F-1) |
| `popstorepush-mandatory.click` | an AVP with flags `40` survives the element's decode and re-encode: the second output carries it again with M set (DW-1) |
| `popstorepush-length-overflow.click` | a maximal message plus the stored maximal AVP would reach 33,554,404 octets, so the packet is dropped (DW-4) |
| `popstorepush-store-retained.click` | the overflow drop keeps the stored AVP: a later 20-octet message carries it on output 1, so a drop that clears the store fails the run (DW-4) |
| `no-avp.click` | a header-only message forwarded unchanged by both pop elements |
| `malformed-version-decap.click` | a 20-octet Version 2 request dropped by `DiameterDecap`, no payload forwarded (A-5, RFC 6733 §3) |
| `malformed-version-pushavp.click` | the same frame dropped by `DiameterPushAVP` rather than appended to (A-5) |
| `malformed-version-popavp.click` | the same frame dropped by `DiameterPopAVP` (A-5) |
| `malformed-version-popstorepush.click` | the same frame dropped by `DiameterPopStorePushAVP`, nothing stored (A-5) |
| `malformed-version-flip-request.click` | the same frame dropped by `DiameterFlipRequest` rather than re-encoded (A-5) |
| `malformed-version-length.click` | Version 2 and Length 100 on one frame: the Version reason wins (A-5) |
| `malformed-version-short.click` | a 3-octet frame starting `02`: the Version reason wins over the short-header reason (A-5) |
| `malformed-empty-packet.click` | a zero-octet packet: the one-octet guard reports the short header instead of reading a Version (A-5) |
| `malformed-short-packet.click` | a 4-octet packet dropped by `DiameterDecap` (F-6) |
| `malformed-avpdecap-short.click` | a 6-octet packet dropped by `DiameterAvpDecap` (F-6) |
| `malformed-avpdecap-v-short.click` | an 8-octet `V` AVP dropped by `DiameterAvpDecap` (F-6) |
| `malformed-avpdecap-vendor-id-zero.click` | a 12-octet `V` AVP with Vendor-Id 0 dropped by `DiameterAvpDecap` (A-6, RFC 6733 §4.1.1) |
| `malformed-avpdecap-vendor-id-zero-length.click` | a zero Vendor-Id AVP whose Length is below its header reports the Length reason first |
| `malformed-avp-in-message-vendor-id-zero.click` | the same AVP inside a message dropped by `DiameterPopAVP` (A-6) |
| `malformed-avp-in-message-pushavp-vendor-id-zero.click` | the same AVP inside a message dropped by `DiameterPushAVP` (A-6) |
| `malformed-avp-in-message-popstorepush-vendor-id-zero.click` | the same AVP inside a message dropped by `DiameterPopStorePushAVP` (A-6) |
| `malformed-zero-length-avp.click` | a zero-length AVP dropped by `DiameterPopAVP`, no hang (F-2) |
| `malformed-avp-short-length.click` | an AVP length below its header dropped by `DiameterPopAVP` |
| `malformed-avp-past-message.click` | an AVP past the message end dropped by `DiameterPopAVP` |
| `malformed-pushavp-length.click` | a header Length beyond the packet dropped by `DiameterPushAVP` (F-3) |
| `malformed-length-short.click` | a header Length below the packet length dropped by `DiameterPushAVP` |
| `malformed-popstorepush-avp-length.click` | a zero-length AVP dropped by `DiameterPopStorePushAVP` |
| `malformed-popstorepush-armed.click` | a malformed second pass dropped by `DiameterPopStorePushAVP` with an AVP armed |
| `malformed-avp-padding-overhang.click` | a 30-octet frame with an unaligned Length dropped by `DiameterPopAVP` for the header rule, ahead of the padded-AVP bound check the frame was built to reach (A-4) |
| `malformed-avp-trailing-octets.click` | a 32-octet aligned frame with four trailing octets: the partial second AVP header is still dropped by `DiameterPopAVP` (A-4) |
| `malformed-decap-length.click` | an aligned Length mismatch dropped by `DiameterDecap` |
| `malformed-length-not-aligned.click` | a 25-octet frame whose Length says 25 dropped by `DiameterDecap` with `the Length field is not a multiple of 4` (A-4, RFC 6733 §3) |
| `malformed-length-not-aligned-pushavp.click` | the same frame dropped by `DiameterPushAVP` rather than appended to (A-4) |
| `malformed-length-not-aligned-mismatch.click` | a 24-octet frame whose Length says 25 reports the alignment reason, not the mismatch (A-4) |
| `malformed-version-not-aligned.click` | a Version 2 frame whose Length says 25 reports the Version reason, not the alignment (A-4) |
| `malformed-short-not-aligned.click` | a 10-octet frame declaring 25 reports the short-header reason, not the alignment (A-4) |
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
that, so a regression to an unpadded AVP fails the run. A message's Length is a
multiple of 4 because it covers the header and the padded AVPs (RFC 6733 §3),
which `encap-unaligned-payload` pins on the writer side and the header
validators enforce on the reader side. The drop tests are the
exception: they assert no forwarded bytes at all, only the one warning line, so
a silent drop or a forwarded malformed packet fails. A frame that carries both a
bad Version and a bad Length, or a bad Version and a truncated header, reports
the Version reason, because the Version test runs before the Length comparison
and the short-header guard; a one-octet guard keeps the Version test from reading
an empty buffer, so a zero-octet packet still reports the short header. A frame
whose Length field is not a multiple of 4 reports the alignment reason, which
outranks a Length mismatch but not the Version or short-header reasons. A frame
that carries both a bad Length
and a prohibited flag reports the Length reason, because the flag test runs only
once the Length matches. `encap-error-on-request`,
`encap-retransmit-on-answer`, `encap-code-too-large`,
`rated-source-code-too-large`, `push-avp-vendor-missing` and
`push-avp-vendor-zero` assert the configure path instead: a non-zero exit,
Click's whole configure-failure output with the named argument, and no `Print`
line, so an element that accepts the pair, writes a zero Vendor-Id or truncates
a Command Code fails the run. The two `*-vendor-id-zero` configs assert the
receive side of the same rule:
`V` set with Vendor-Id 0 is dropped by `DiameterAvpDecap` for one AVP and by
`DiameterPopAVP` inside a message, with the reason `the V bit is set with a zero
Vendor-Id`.

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
