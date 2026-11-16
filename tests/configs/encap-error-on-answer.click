require(diameter);

// E is legal on an answer, so ERROR true with REQUEST false configures and
// emits flags 20. Identifiers are random (F-11) and the test regexes them.
InfiniteSource(DATA \<de ad be ef>, LIMIT 1, STOP true)
-> DiameterEncap(CODE 280, REQUEST false, ERROR true)
-> Print(encap-error-on-answer, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
