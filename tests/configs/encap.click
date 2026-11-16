require(diameter);

// F-4: every header field is initialized, so version is 1 and Length counts the
// 20-octet header plus the payload -- 24 for these 4 octets. The config sets no
// seed, so the identifiers vary per run and the test regexes them; everything
// else is pinned, so a version or Length regression fails the run.
InfiniteSource(DATA \<de ad be ef>, LIMIT 1, STOP true)
-> DiameterEncap(CODE 280, REQUEST true)
-> Print(encap, MAXLENGTH 200, CONTENTS HEX)
-> Discard;