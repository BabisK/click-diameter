require(diameter);

// A-4: a 7-octet payload gains one zero pad octet, so the frame is 28 octets
// with Length 0x1c. The residue pins the padding formula beside the two- and
// three-octet cases. The config sets no seed, so the identifiers vary per run
// and the test regexes them.
InfiniteSource(DATA \<de ad be ef 00 11 22>, LIMIT 1, STOP true)
-> DiameterEncap(CODE 280, REQUEST true)
-> Print(encap-padding-one, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
