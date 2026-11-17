require(diameter);

// A-4: a 6-octet payload gains two zero pad octets, so the frame is 28 octets
// with Length 0x1c. The residue pins the padding formula beside the three- and
// one-octet cases. The config sets no seed, so the identifiers vary per run and
// the test regexes them.
InfiniteSource(DATA \<de ad be ef 00 11>, LIMIT 1, STOP true)
-> DiameterEncap(CODE 280, REQUEST true)
-> Print(encap-padding-two, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
