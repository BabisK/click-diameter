require(diameter);

// CAP-5: RFC 6733 section 3 forbids P on an answer, so configure must fail and
// nothing may reach Print.
InfiniteSource(DATA \<de ad be ef>, LIMIT 1, STOP true)
-> DiameterEncap(CODE 280, REQUEST false, PROXIABLE true)
-> Print(encap-proxiable-on-answer, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
