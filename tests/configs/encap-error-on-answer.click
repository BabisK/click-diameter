require(diameter);

// E is legal on an answer, so ERROR true with REQUEST false configures and
// emits flags 20. The config sets no seed, so the identifiers vary per run and
// the test regexes them.
InfiniteSource(DATA \<de ad be ef>, LIMIT 1, STOP true)
-> DiameterEncap(CODE 280, REQUEST false, ERROR true)
-> Print(encap-error-on-answer, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
