require(diameter);

// CAP-5: RFC 6733 section 3 forbids E on a request, so configure must fail and
// nothing may reach Print.
InfiniteSource(DATA \<de ad be ef>, LIMIT 1, STOP true)
-> DiameterEncap(CODE 280, REQUEST true, ERROR true)
-> Print(encap-error-on-request, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
