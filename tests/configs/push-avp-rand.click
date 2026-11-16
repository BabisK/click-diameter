require(diameter);

// Generated value: 8 hex characters, so a 16-byte AVP body including padding.
InfiniteSource(DATA \<01 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterPushAVP(CODE 264, RANDALPHANUMSTRING 8)
-> Print(push-avp-rand, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
