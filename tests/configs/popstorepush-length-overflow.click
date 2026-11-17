require(diameter);

// DW-4: both packets carry a maximal 16,777,212-octet message with a 16 MB
// AVP. The first pass pops and stores the AVP (output 0 is the 20-octet
// header); the second pushes it back onto another maximal message, which would
// reach 33,554,404 octets, so the packet is dropped and the stored AVP kept
// for a later packet.
InfiniteSource(DATA \<01 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 2, STOP true)
-> DiameterPushAVP(CODE 264, RANDHEXSTRING 16777184)
-> psp :: DiameterPopStorePushAVP;
psp[0] -> Print(out0, MAXLENGTH 40, CONTENTS HEX) -> Discard;
psp[1] -> Print(out1, MAXLENGTH 200, CONTENTS HEX) -> Discard;
