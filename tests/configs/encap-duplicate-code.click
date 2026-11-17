require(diameter);

// DW-2: a repeated keyword fails configuration naming it instead of keeping
// the last value and silently discarding the first.
InfiniteSource(DATA \<de ad be ef>, LIMIT 1, STOP true)
-> DiameterEncap(CODE 280, REQUEST true, CODE 281)
-> Print(encap-duplicate-code, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
