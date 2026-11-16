require(diameter);

// Answer in: the flip sets R and leaves every other octet alone, so the flags
// byte goes from 00 to 80.
InfiniteSource(DATA \<01 00 00 14 00 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterFlipRequest()
-> Print(flip-answer, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
