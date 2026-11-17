require(diameter);

// F-11: the pull path advances the same identifier counters as the task path,
// each seeded once from click_random(), so two messages in one run differ and
// the same seed reproduces both runs byte for byte. The first frame is pinned
// by the test: a swap of the two nextX() calls or an extra draw in pull()
// moves it. identifiers-rated-source-pull-unique covers the refused pulls
// between the frames.
RandomSeed(SEED 12345);
DiameterRatedSource(CODE 280, REQUEST true, APPID 42, RATE 10, LIMIT 2, STOP true)
-> Unqueue()
-> Print(rated-source-pull, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
