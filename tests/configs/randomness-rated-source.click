require(diameter);

// F-11: a generated header's identifiers come from Click's RNG, so RandomSeed
// pins them. Two messages in one run differ; the same seed reproduces both runs
// byte for byte. The test rewrites the seed and reruns after a second.
RandomSeed(SEED 12345);
DiameterRatedSource(CODE 280, REQUEST true, APPID 42, LIMIT 2, STOP true)
-> Print(rated-source, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
