require(diameter);

// RFC 6733 section 3 forbids T in an answer. The header is well-formed and the
// Length matches, so the flip reports the flag reason and forwards nothing.
InfiniteSource(DATA \<01 00 00 14 10 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterFlipRequest()
-> Print(flip-request, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
