require(diameter);

// T is legal on a request and is not checked: RETRANSMITED true emits flags 90.
// The config sets no seed, so the identifiers vary per run and the test regexes
// them.
InfiniteSource(DATA \<de ad be ef>, LIMIT 1, STOP true)
-> DiameterEncap(CODE 280, REQUEST true, RETRANSMITED true)
-> Print(encap-retransmit-on-request, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
