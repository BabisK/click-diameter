require(diameter);

// RFC 6733 section 6.2 sets an answer's P to the same value as the request's, so
// a proxiable request flips to an answer with R cleared and P kept: c0 to 40.
InfiniteSource(DATA \<01 00 00 14 c0 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterFlipRequest()
-> Print(flip-request-p, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
