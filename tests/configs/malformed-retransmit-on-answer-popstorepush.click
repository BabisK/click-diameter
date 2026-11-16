require(diameter);

// The pop-store-push element shares diameter_check_message, so a T-bearing
// answer is dropped before anything is stored and neither output sees a packet.
InfiniteSource(DATA \<01 00 00 14 10 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> psp :: DiameterPopStorePushAVP;
psp[0] -> Print(pop-store-push, MAXLENGTH 200, CONTENTS HEX) -> Discard;
psp[1] -> Discard;
