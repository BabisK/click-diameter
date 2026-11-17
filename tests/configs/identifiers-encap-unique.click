require(diameter);

// The 240 000-message repro for the first writer: 32 random bits cannot keep
// that many values distinct, while the per-message identifier counters can.
// The helper requires 240 000 distinct hop-by-hop and end-to-end values, no
// frame whose two identifiers agree, and a byte-identical second run.
RandomSeed(SEED 12345);
InfiniteSource(DATA \<de ad be ef>, LIMIT 240000, STOP true)
-> DiameterEncap(CODE 280, REQUEST true)
-> Print(ids, MAXLENGTH 20, CONTENTS HEX)
-> Discard;
