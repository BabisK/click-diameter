require(diameter);

// F-10: a proxiable request in, an answer out. R and P both clear, because
// RFC 6733 section 3 forbids P on an answer.
InfiniteSource(DATA \<01 00 00 14 c0 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterFlipRequest()
-> Print(flip-request-p, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
