require(diameter);

// F-11: the pull path draws the same identifiers as the task path, so
// RandomSeed pins them. Unqueue pulls two messages in one run; they differ, and
// the same seed reproduces both runs byte for byte. The test rewrites the seed
// and reruns after a second.
RandomSeed(SEED 12345);
DiameterRatedSource(CODE 280, REQUEST true, APPID 42, LIMIT 2, STOP true)
-> Unqueue()
-> Print(rated-source-pull, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
