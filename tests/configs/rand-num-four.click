require(diameter);

// RANDNUMSTRING keeps its alphabet: four digits, AVP Length 12, no padding.
InfiniteSource(DATA \<01 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterPushAVP(CODE 264, RANDNUMSTRING 4)
-> Print(rand-num-four, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
