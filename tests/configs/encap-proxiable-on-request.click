require(diameter);

// The accept side of the P guard: P is the one flag an answer may not carry in
// this package, so a proxiable request configures and emits flags c0. A guard
// that rejected every PROXIABLE use fails here. Identifiers are random (F-11)
// and the test regexes them.
InfiniteSource(DATA \<de ad be ef>, LIMIT 1, STOP true)
-> DiameterEncap(CODE 280, REQUEST true, PROXIABLE true)
-> Print(encap-proxiable-on-request, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
