require(diameter);

// P is legal on either message type, so a proxiable request configures and
// emits flags c0. A guard that rejected every PROXIABLE use fails here.
// The config sets no seed, so the identifiers vary per run and the test regexes
// them.
InfiniteSource(DATA \<de ad be ef>, LIMIT 1, STOP true)
-> DiameterEncap(CODE 280, REQUEST true, PROXIABLE true)
-> Print(encap-proxiable-on-request, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
