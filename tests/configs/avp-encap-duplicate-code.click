require(diameter);

// DW-2: a repeated keyword fails configuration naming it instead of keeping the
// last value and silently discarding the first. DiameterAvpEncap is the fourth
// element that takes keyword arguments, so it runs the same guard.
InfiniteSource(DATA \<61 62 63 64>, LIMIT 1, STOP true)
-> DiameterAvpEncap(CODE 264, CODE 8)
-> Print(avp-encap-duplicate-code, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
