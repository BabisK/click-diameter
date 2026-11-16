require(diameter);

// Length 24, so stripping the 20-byte header leaves the 4-byte payload.
InfiniteSource(DATA \<01 00 00 18 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02 de ad be ef>, LIMIT 1, STOP true)
-> DiameterDecap()
-> Print(decap, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
