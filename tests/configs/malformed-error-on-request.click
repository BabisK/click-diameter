require(diameter);

// RFC 6733 section 3 forbids E in a request. The header is well-formed and the
// Length matches, so the flag reason is the one the decapsulator reports.
InfiniteSource(DATA \<01 00 00 18 a0 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02 de ad be ef>, LIMIT 1, STOP true)
-> DiameterDecap()
-> Print(decap, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
