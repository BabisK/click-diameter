require(diameter);

// A proxiable error answer flips to a proxiable request: P is kept and E is
// cleared, flags 60 to c0, per RFC 6733 sections 3 and 6.2.
InfiniteSource(DATA \<01 00 00 14 60 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterFlipRequest()
-> Print(flip-answer-ep, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
