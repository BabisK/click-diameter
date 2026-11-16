require(diameter);

// RFC 6733 section 3 forbids T in an answer, so configure must fail and nothing
// may reach Print.
InfiniteSource(DATA \<de ad be ef>, LIMIT 1, STOP true)
-> DiameterEncap(CODE 280, REQUEST false, RETRANSMITED true)
-> Print(encap-retransmit-on-answer, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
