require(diameter);

// The story's rate-shaped repro for the second writer: 1 000 messages per
// second for four minutes of Click's simulated time, through the token bucket.
// The helper requires 240 000 distinct hop-by-hop and end-to-end values, so a
// counter that steps on a refused token fails the count, and a byte-identical
// second run.
RandomSeed(SEED 12345);
DiameterRatedSource(CODE 280, REQUEST true, RATE 1000, LIMIT 240000, STOP true)
-> Print(ids, MAXLENGTH 20, CONTENTS HEX)
-> Discard;
