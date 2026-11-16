require(diameter);

// F-11: the identifiers come from Click's RNG, so RandomSeed pins them. Two
// packets in one run draw twice and differ; the same seed reproduces both runs
// byte for byte. The test rewrites the seed and reruns after a second.
RandomSeed(SEED 12345);
InfiniteSource(DATA \<de ad be ef>, LIMIT 2, STOP true)
-> DiameterEncap(CODE 280, REQUEST true)
-> Print(encap, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
