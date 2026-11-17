require(diameter);

// F-11: each identifier starts from a RandomSeed draw at initialization and
// then advances by one per message, so two packets in one run differ and the
// same seed reproduces both runs byte for byte. The test rewrites the seed and
// reruns after a second.
RandomSeed(SEED 12345);
InfiniteSource(DATA \<de ad be ef>, LIMIT 2, STOP true)
-> DiameterEncap(CODE 280, REQUEST true)
-> Print(encap, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
