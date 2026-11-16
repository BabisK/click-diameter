require(diameter);

// Request in, answer out: the R bit must clear.
InfiniteSource(DATA \<01 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterFlipRequest()
-> Print(flip-request, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
