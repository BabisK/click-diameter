require(diameter);

// An answer that carries P flips to c0: R is set and P is kept. Mirrored P is
// what RFC 6733 section 6.2 asks of a generated answer, so the flip preserves it
// in both directions rather than treating a P-bearing answer as an error.
InfiniteSource(DATA \<01 00 00 14 40 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterFlipRequest()
-> Print(flip-answer-p, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
