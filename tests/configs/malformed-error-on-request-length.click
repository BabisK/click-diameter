require(diameter);

// Both faults in one frame: the declared Length is 100 on 24 octets and the
// request carries E. The Length reason is reported first, because the flag test
// runs only once the Length matches the packet.
InfiniteSource(DATA \<01 00 00 64 a0 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02 de ad be ef>, LIMIT 1, STOP true)
-> DiameterDecap()
-> Print(decap, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
