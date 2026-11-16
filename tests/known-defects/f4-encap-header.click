require(diameter);

// F-4: the header is never initialized. Version is uninitialized garbage
// (0x2a, 0xde, 0xe2 observed) and Length counts the 4-byte payload instead of
// payload + 20. Expect version 1 and Length 24 once fixed.
InfiniteSource(DATA \<de ad be ef>, LIMIT 1, STOP true)
-> DiameterEncap(CODE 280, REQUEST true)
-> Print(encap, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
