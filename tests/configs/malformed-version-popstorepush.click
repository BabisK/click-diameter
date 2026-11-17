require(diameter);

// A-5: the 20-octet frame declares Version 2, which RFC 6733 section 3 forbids.
// DiameterPopStorePushAVP must drop it before storing, so neither output sees
// a packet.
InfiniteSource(DATA \<02 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> psp :: DiameterPopStorePushAVP;
psp[0] -> Print(pop-store-push, MAXLENGTH 200, CONTENTS HEX) -> Discard;
psp[1] -> Discard;
