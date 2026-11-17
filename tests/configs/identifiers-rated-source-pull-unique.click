require(diameter);

// CAP-4 on the pull path: RATE 10 leaves refused pulls between the three
// returned packets, so a counter advanced before the token-bucket refusal skips
// a value and the frames are no longer consecutive. This is the pull twin of
// identifiers-rated-source-unique, which covers the push task.
RandomSeed(SEED 12345);
DiameterRatedSource(CODE 280, REQUEST true, APPID 42, RATE 10, LIMIT 3, STOP true)
-> Unqueue()
-> Print(ids, MAXLENGTH 20, CONTENTS HEX)
-> Discard;
