require(diameter);

// RFC 6733 section 6.2 has an answer mirror the request's P, and Encap has no
// request to consult, so PROXIABLE on an answer configures and emits flags 40.
// Identifiers are random (F-11) and the test regexes them.
InfiniteSource(DATA \<de ad be ef>, LIMIT 1, STOP true)
-> DiameterEncap(CODE 280, REQUEST false, PROXIABLE true)
-> Print(encap-proxiable-on-answer, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
