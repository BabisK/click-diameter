require(diameter);

// F-8: a count of 1 must emit one character, not an empty AVP. AVP Length 9,
// padded to 12 octets, so the message is 32 octets.
InfiniteSource(DATA \<01 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterPushAVP(CODE 264, RANDALPHANUMSTRING 1)
-> Print(rand-alphanum-one, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
