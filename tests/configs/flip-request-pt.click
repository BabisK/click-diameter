require(diameter);

// A proxiable retransmission flips to an answer that keeps P and clears T with
// R: flags d0 to 40, per RFC 6733 sections 3 and 6.2.
InfiniteSource(DATA \<01 00 00 14 d0 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterFlipRequest()
-> Print(flip-request-pt, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
