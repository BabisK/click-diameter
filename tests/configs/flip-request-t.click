require(diameter);

// T on a request is not checked: RFC 6733 section 3 allows it only as a
// retransmission marker, which a stateless element cannot judge. In an answer it
// is forbidden, so the flip clears it together with R: flags 90 to 00.
InfiniteSource(DATA \<01 00 00 14 90 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterFlipRequest()
-> Print(flip-request-t, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
