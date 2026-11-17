require(diameter);

// F-4: Encap's Length covers the whole frame and Decap validates that frame, so
// the payload must itself be an AVP sequence. It is one 8-octet AVP (code 264,
// no value), which Decap forwards unchanged after stripping the header. The
// config sets no seed, so the identifiers vary per run; the test regexes them.
InfiniteSource(DATA \<00 00 01 08 00 00 00 08>, LIMIT 1, STOP true)
-> DiameterEncap(CODE 280, REQUEST true)
-> Print(encap, MAXLENGTH 200, CONTENTS HEX)
-> DiameterDecap()
-> Print(decap, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
