require(diameter);

// The largest Command Code the three-octet field holds (RFC 6733 section 3) is
// 16777215 (0xFFFFFF), and section 3.1 reserves it for experimental use, so it
// is in range: the guard is inclusive and the frame carries ffffff.
InfiniteSource(DATA \<de ad be ef>, LIMIT 1, STOP true)
-> DiameterEncap(CODE 16777215, REQUEST true)
-> Print(encap-code-max, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
