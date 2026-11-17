require(diameter);

// F-11: each identifier starts from a RandomSeed draw at initialization and
// then advances by one per emitted message, so two messages in one run differ
// and the same seed reproduces both runs byte for byte. The test rewrites the
// seed and reruns after a second.
RandomSeed(SEED 12345);
DiameterRatedSource(CODE 280, REQUEST true, APPID 42, LIMIT 2, STOP true)
-> Print(rated-source, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
