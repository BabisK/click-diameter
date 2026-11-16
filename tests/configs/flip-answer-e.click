require(diameter);

// E is legal on an answer, but RFC 6733 section 3 forbids it in a request, so
// the flip clears it as it sets R: flags 20 to 80.
InfiniteSource(DATA \<01 00 00 14 20 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterFlipRequest()
-> Print(flip-answer-e, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
