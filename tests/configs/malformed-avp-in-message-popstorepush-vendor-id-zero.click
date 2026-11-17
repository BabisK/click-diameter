require(diameter);

// DiameterPopStorePushAVP walks the message with the same check, so a V=1,
// Vendor-Id=0 AVP is dropped before anything is stored and neither output sees
// a packet.
InfiniteSource(DATA \<01 00 00 20 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02 00 00 01 08 80 00 00 0c 00 00 00 00>, LIMIT 1, STOP true)
-> psp :: DiameterPopStorePushAVP;
psp[0] -> Print(pop-store-push, MAXLENGTH 200, CONTENTS HEX) -> Discard;
psp[1] -> Discard;
