require(diameter);

// F-8: one hex character, AVP Length 9 rather than an 8-octet header-only AVP.
InfiniteSource(DATA \<01 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterPushAVP(CODE 264, RANDHEXSTRING 1)
-> Print(rand-hex-one, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
