require(diameter);

// F-11: the pull path advances the same identifier counters as the task path,
// each seeded once from click_random(), so two messages in one run differ and
// the same seed reproduces both runs byte for byte. The test rewrites the seed
// and reruns after a second.
RandomSeed(SEED 12345);
DiameterRatedSource(CODE 280, REQUEST true, APPID 42, LIMIT 2, STOP true)
-> Unqueue()
-> Print(rated-source-pull, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
