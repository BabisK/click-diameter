require(diameter);

// A-9: the Command Code is a three-octet field (RFC 6733 section 3), so
// 16777496 (0x01000118) cannot be written: it would go out as 0x000118, a
// different message type. Configure must fail and nothing may reach Print.
InfiniteSource(DATA \<de ad be ef>, LIMIT 1, STOP true)
-> DiameterEncap(CODE 16777496, REQUEST true)
-> Print(encap-code-too-large, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
