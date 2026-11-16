require(diameter);

// F-11: the RANDUINT32 value comes from Click's RNG, so RandomSeed pins it. Two
// header-only requests in one run get different values; the same seed
// reproduces both runs byte for byte. The test rewrites the seed and reruns
// after a second.
RandomSeed(SEED 12345);
InfiniteSource(DATA \<01 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 2, STOP true)
-> DiameterPushAVP(CODE 264, RANDUINT32 true)
-> Print(push-avp-uint32, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
