require(diameter);

// V-6: the identifier counters consume no per-packet draws, so a seeded writer
// leaves the rest of Click's stream at a fixed position. Chaining a RAND*
// generator here pins both the seed and that position: the first appended value
// is the third draw, and the second message carries the next counters and the
// next draw. Moving the draws changed these bytes, and nothing else in the suite
// pairs a seeded writer with a generator.
RandomSeed(SEED 12345);
InfiniteSource(DATA \<00 00 01 08 00 00 00 08>, LIMIT 2, STOP true)
-> DiameterEncap(CODE 280, REQUEST true)
-> DiameterPushAVP(CODE 264, RANDHEXSTRING 8)
-> Print(mix, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
