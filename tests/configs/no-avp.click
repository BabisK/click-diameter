require(diameter);

// A header-only message has no AVP to pop, and popping nothing is a no-op, not
// malformed: both pop elements forward it unchanged with no warning.
InfiniteSource(DATA \<01 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterPopAVP()
-> Print(pop-avp, MAXLENGTH 200, CONTENTS HEX)
-> psp :: DiameterPopStorePushAVP;
psp[0] -> Print(pop-store-push, MAXLENGTH 200, CONTENTS HEX) -> Discard;
psp[1] -> Discard;
