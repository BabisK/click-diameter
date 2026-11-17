require(diameter);

// A-5: the 20-octet frame declares Version 2, which RFC 6733 section 3 forbids.
// DiameterPopAVP must drop it rather than forward the header with the bogus
// Version copied through.
InfiniteSource(DATA \<02 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterPopAVP()
-> Print(pop-avp, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
