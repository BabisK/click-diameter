require(diameter);

// F-4: Encap's Length now covers the whole frame, so Decap accepts what Encap
// produced instead of dropping it as malformed, and forwards the payload
// unchanged. The config sets no seed, so the identifiers vary per run; the test
// regexes them.
InfiniteSource(DATA \<de ad be ef>, LIMIT 1, STOP true)
-> DiameterEncap(CODE 280, REQUEST true)
-> Print(encap, MAXLENGTH 200, CONTENTS HEX)
-> DiameterDecap()
-> Print(decap, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
