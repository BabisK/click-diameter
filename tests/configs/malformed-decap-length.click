require(diameter);

// The header declares Length 100 for a 24-octet packet. The decapsulator must
// not strip the header and forward four octets of a frame it cannot trust.
InfiniteSource(DATA \<01 00 00 64 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02 de ad be ef>, LIMIT 1, STOP true)
-> DiameterDecap()
-> Print(decap, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
