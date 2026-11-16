require(diameter);

// The store path validates before it allocates: the trailing AVP declares
// length 0, so nothing is stored and the packet is dropped.
InfiniteSource(DATA \<01 00 00 20 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02 00 00 01 08 00 00 00 00 00 00 00 00>, LIMIT 1, STOP true)
-> psp :: DiameterPopStorePushAVP;
psp[0] -> Print(out0, MAXLENGTH 200, CONTENTS HEX) -> Discard;
psp[1] -> Print(out1, MAXLENGTH 200, CONTENTS HEX) -> Discard;
