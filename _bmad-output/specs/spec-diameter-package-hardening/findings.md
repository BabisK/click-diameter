# Review Findings

Evidence for every defect this spec defers. Baseline: `kohler/click` master `9197a594b`, built from a pristine `git archive` in WSL (Ubuntu 26.04, GCC 15.2) with `./configure --disable-linuxmodule`, then the package with `./configure --with-click=$PREFIX --prefix=$PREFIX`. The package built with 0 warnings and all 9 elements registered; every finding below is behavioral, packaging-level, or read directly from source.

Severity is impact if the defect reaches a user, not effort to fix. Capability links point into `SPEC.md`.

## F-1 â€” `DiameterPopStorePushAVP` heap overflow (critical)

- **Where:** `src/diameterpopstorepushavp.cc:76-77`
- **Symptom:** Click aborts with `*** buffer overflow detected ***`, exit 134.
- **Cause:** `data = new uint8_t[ah.getLength() - headerLength]` allocates the unpadded AVP body (2 bytes for an AVP of length 10), but `memcpy` copies `ah.getLengthPadded() - headerLength` bytes (4).
- **Trigger:** any AVP whose length is not a multiple of 4, which is normal traffic.
- **Capability:** CAP-1

## F-2 â€” `DiameterPopAVP` infinite loop on a zero-length AVP (critical)

- **Where:** `src/diameterpopavp.cc:35-40`, `src/diameter.hh:218`
- **Symptom:** the process never terminates; killed at a 10 s timeout, exit 124.
- **Cause:** `getLengthPadded()` returns 0 for an AVP whose length field is 0, so `nextAvp()` never advances and the scan loops forever.
- **Capability:** CAP-1

## F-3 â€” `DiameterPushAVP` writes outside the packet (critical)

- **Where:** `src/diameterpushavp.cc:151-171`
- **Symptom:** with a header length field of 100 in a 20-byte packet, the element wrote at offset +100 and set the declared length to 112, with no error. Output `01000070 80000118 ...` (32 bytes dumped, declared length 112).
- **Cause:** the write offset is `dh.getLength()` from the packet contents, not `p->length()`, and there is no bounds or consistency check.
- **Capability:** CAP-1

## F-4 â€” `DiameterEncap` emits invalid headers (high)

- **Where:** `src/diameter.hh:23`, `src/diameterencap.cc:56-65`
- **Symptom:** `2a000004 80000118 ...` for a 4-byte payload: version byte `0x2a` (also `0xde`, `0xe2` across runs) and Length 4, the payload only.
- **Cause:** `DiameterHeader` has no constructor, so version, flags, code, and the identifiers are indeterminate; the encap path sets only some fields and writes only the payload length into the Length field.
- **RFC:** 6733 Â§3 â€” version is 1, Length counts the 20-byte header plus all AVPs.
- **Capability:** CAP-2

## F-5 â€” `DiameterRatedSource` emits invalid flags (high)

- **Where:** `src/diameterratedsource.cc:68-72`
- **Symptom:** generated requests show flags `0xe0` â€” E=1 on a request.
- **Cause:** `proxiable`, `error`, and `retransmitted` are never assigned, so their values are whatever the backing struct holds.
- **Capability:** CAP-5

## F-6 â€” Decapsulators do not length-check (high)

- **Where:** `src/diameterdecap.cc`, `src/diameteravpdecap.cc`
- **Symptom:** on a 4-byte packet, `DiameterDecap` logs `Packet::pull 20 > length 4` and forwards a 0-length packet; `DiameterAvpDecap` logs `Packet::pull 8 > length 4` and does the same.
- **Cause:** the pull result is not checked for failure before the element continues and pushes the packet to its output.
- **Capability:** CAP-1

## F-7 â€” No 4-octet AVP padding (high)

- **Where:** `src/diameteravpencap.cc`, `src/diameteravpdecap.cc`
- **Symptom:** an 8-byte header plus a 5-byte payload produced 13 bytes; RFC 6733 Â§4.1 requires 16.
- **Cause:** encode writes the raw payload length with no padding; decode never strips padding, so a following AVP is read 3 bytes early.
- **Capability:** CAP-3

## F-8 â€” `RANDALPHANUMSTRING` yields an empty AVP (medium)

- **Where:** `src/diameterpushavp.cc:130`
- **Symptom:** `RANDALPHANUMSTRING 1` produced a 28-byte packet ending `00000108 00000008` â€” an AVP with no data.
- **Cause:** the length comparison is written as `> true`, a boolean comparison that is false for every positive count.
- **Capability:** CAP-4

## F-9 â€” Hex alphabet contains invalid characters (medium)

- **Where:** `src/diameterpushavp.cc:47-50`
- **Symptom (source inspection):** the literal is `"0123456789ABCDEFG" "abcdefg"`, so generation can emit `G`/`g` and duplicates A-F in both cases.
- **Capability:** CAP-4

## F-10 â€” `DiameterFlipRequest` flips only R (medium)

- **Where:** `src/diameterfliprequest.cc`
- **Symptom:** a request's flags go `0x80` to `0x00`; an answer keeps P=1, which RFC 6733 Â§3 forbids (P is meaningful only on requests).
- **Capability:** CAP-5

## F-11 â€” Global RNG reseeding (medium)

- **Where:** `src/diameterratedsource.cc`, `src/diameterpushavp.cc`, `src/diameterinfinitesource.cc`
- **Symptom (source inspection):** each element calls `srand(time(NULL))` and `rand()`, reseeding the process-wide C RNG and making runs unreproducible.
- **Capability:** CAP-6

## F-12 â€” No man pages installed (packaging)

- **Symptom:** `share/man/man7` contains 280 Click pages and 0 diameter pages; `click-elem2man` exits 0 while writing nothing.
- **Cause:** no element carries `=c`/`=d` documentation sections, so there is nothing to render.
- **Capability:** CAP-7

## F-13 â€” README install recipe fails as written (packaging)

- **Symptom:** `README.md` says only `autoconf; ./configure; make; make install`. Without `--with-click` the package cannot find Click; without `--prefix` it installs under `/usr/local`, which needs root and is not on Click's search path.
- **Capability:** CAP-7

## F-14 â€” Package identity is inconsistent (packaging)

- **Symptom:** `AC_INIT(click-diameterpackage, 2.0.1)` â€” an odd tarball name, and version 2.0.1 is unrelated to the Click version it targets.
- **Capability:** CAP-8

## F-15 â€” Stale guards, includes, and dead code (packaging)

- **Symptom (source inspection):** guards do not match filenames (`DIAMETERAPPENDAVP_HH_`, `DIAMETERPOPSTOREUSHAVP_HH_`, `DIAMETER_HH_` / `DIAMETERINFINITESOURCE_HH_`); `<iostream>` appears in data-path elements, which the kernel and BSD package targets cannot use; `DiameterPopStorePushAVP` carries a dead `simple_action()` beside `push()`.
- **Capability:** CAP-8

## F-16 â€” Click fork still contains the in-tree copy and a broken test (packaging)

- **Where:** `babisk/diameter` commit `9f136402d` (`conf/test.click`, `etc/diameter/`)
- **Symptom:** the committed `conf/test.click`, run as-is, fails to configure:
  ```
  RATE: invalid number / ACTIVE: parse error / CODE: required argument missing
  REQUEST: required argument missing / LENGTH: unknown argument
  ```
  `etc/diameter/` duplicates the package that now lives out-of-tree.
- **Capability:** CAP-8

## Verified-correct behavior (do not regress)

Against well-formed input: `DiameterPushAVP` appends an AVP and updates Length (20 to 32 bytes, AVP `00000108 0000000b 61626300`); `DiameterPopAVP` removes the last AVP and fixes Length (44 to 32, first AVP intact); `DiameterFlipRequest` clears R (`0x80` to `0x00`); `DiameterAvpEncap` then `DiameterAvpDecap` round-trips a payload; and missing or unknown arguments are reported by name (`CODE: required argument missing`, `BOGUS: unknown argument`).

## Not defects

- `click-buildtool.in` has one CRLF line in the git index on **both** `upstream/master` and `babisk/diameter`; it is upstream, not something this package introduced.
- `Print` defaults to `MAXLENGTH 24`, which silently truncates test dumps. Every repro config below passes `MAXLENGTH 200`.

## Reproduction harness

Build (WSL, from a pristine export to avoid the Windows `core.autocrlf` checkout):

```bash
git -C /path/to/click archive 9197a594b | tar -x -C "$HOME/src/click-upstream"
cd "$HOME/src/click-upstream" && ./configure --prefix="$HOME/click-master" --disable-linuxmodule
make -j16 && make install
git -C /path/to/click-diameter archive HEAD | tar -x -C "$HOME/src/pkg"
cd "$HOME/src/pkg" && autoconf && ./configure --with-click="$HOME/click-master" --prefix="$HOME/click-master"
make && make install
```

Representative configs (run with `$HOME/click-master/bin/click cfg.click`):

| Finding | Config body |
|---|---|
| F-1 | `require(diameter); InfiniteSource(DATA \<...44-byte msg with two AVPs...>, LIMIT 2, STOP true) -> psp :: DiameterPopStorePushAVP; psp[0] -> Discard; psp[1] -> Discard;` |
| F-2 | 32-byte message whose AVP has length 0: `01 00 00 20 80 00 01 18 ... 00 00 01 08 00 00 00 00`, then `-> DiameterPopAVP() -> Print(x, MAXLENGTH 200) -> Discard;` |
| F-3 | 20-byte header with Length 100, then `-> DiameterPushAVP(CODE 264, OCTETSTRING "abc") -> Print(x, MAXLENGTH 200) -> Discard;` |
| F-4 | `InfiniteSource(DATA \<de ad be ef>, LIMIT 1, STOP true) -> DiameterEncap(CODE 280, REQUEST true) -> Print(x, MAXLENGTH 200) -> Discard;` |
| F-5 | `DiameterRatedSource(\<0800>, 10, 1000, LENGTH 64) -> Print(x, MAXLENGTH 200) -> Discard;` |
| F-6 | `InfiniteSource(DATA \<01 02 03 04>, LIMIT 1, STOP true) -> DiameterDecap() -> Print(x, MAXLENGTH 200) -> Discard;` (same with `DiameterAvpDecap()`). |
| F-7 | `InfiniteSource(DATA \<61 62 63 64 65>, LIMIT 1, STOP true) -> DiameterAvpEncap(CODE 264) -> Print(x, MAXLENGTH 200) -> Discard;` |
| F-8 | `DiameterPushAVP(CODE 264, RANDALPHANUMSTRING 1)` on a 20-byte header. |
| F-10 | 20-byte **answer** header (flags `0x00`, P bit set in the answer form) then `-> DiameterFlipRequest()`. |
| F-16 | `git -C /path/to/click show 9f136402d:conf/test.click > committed.click && click committed.click` |

The 44-byte two-AVP message used above: `01 00 00 2c 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02 00 00 01 08 00 00 00 0a 61 62 00 00 00 00 01 0c 00 00 00 0a 78 79 00 00`.
