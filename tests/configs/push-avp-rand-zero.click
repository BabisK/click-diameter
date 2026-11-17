require(diameter);

// A zero count is the documented "unused" value, not a supplied source, so
// RANDNUMSTRING 0 beside RANDHEXSTRING 4 configures and the hex generator
// supplies: AVP Length 12 and four hex characters, 32 octets in total.
InfiniteSource(DATA \<01 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterPushAVP(CODE 264, RANDNUMSTRING 0, RANDHEXSTRING 4)
-> Print(push-avp-rand-zero, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
