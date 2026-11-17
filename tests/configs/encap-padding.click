require(diameter);

// A-4: a 5-octet payload is zero-padded to the 4-octet boundary, so the frame is
// 28 octets with Length 0x1c and three zero pad octets after the payload. The
// pad is part of the message, so DiameterDecap forwards it with the payload and
// prints 8 octets rather than dropping the frame. The config sets no seed, so
// the identifiers vary per run and the test regexes them.
InfiniteSource(DATA \<de ad be ef 00>, LIMIT 1, STOP true)
-> DiameterEncap(CODE 280, REQUEST true)
-> Print(encap, MAXLENGTH 200, CONTENTS HEX)
-> DiameterDecap()
-> Print(decap, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
