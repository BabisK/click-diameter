require(diameter);

// A-5: the 20-octet frame declares Version 2, which RFC 6733 section 3 forbids.
// DiameterDecap must drop it and forward no payload.
InfiniteSource(DATA \<02 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterDecap()
-> Print(decap, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
