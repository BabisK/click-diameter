require(diameter);

// AVP length 4 is below the 8-octet header. Dropped before the pop reads the
// AVP, so no out-of-bounds read.
InfiniteSource(DATA \<01 00 00 20 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02 00 00 01 08 00 00 00 04 00 00 00 00>, LIMIT 1, STOP true)
-> DiameterPopAVP()
-> Print(pop-avp, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
