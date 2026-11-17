require(diameter);

// A-9: 16777216 (0x1000000) is the first value the three-octet Command Code
// field cannot hold (RFC 6733 section 3), so configuration must fail here. The
// larger repro value alone lets a guard that is off by up to 0x1000000 pass.
InfiniteSource(DATA \<de ad be ef>, LIMIT 1, STOP true)
-> DiameterEncap(CODE 16777216, REQUEST true)
-> Print(encap-code-first-too-large, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
