require(diameter);

// T is legal on a request and is not checked: RETRANSMITED true emits flags 90.
// Identifiers are random (F-11) and the test regexes them.
InfiniteSource(DATA \<de ad be ef>, LIMIT 1, STOP true)
-> DiameterEncap(CODE 280, REQUEST true, RETRANSMITED true)
-> Print(encap-retransmit-on-request, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
