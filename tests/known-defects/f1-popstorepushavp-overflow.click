require(diameter);

// F-1: heap overflow. Two packets, the first carrying two AVPs; the popped body
// is allocated unpadded but copied padded, so Click aborts with
// "*** buffer overflow detected ***" (exit 134) once fixed input reaches it.
InfiniteSource(DATA \<01 00 00 2c 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02 00 00 01 08 00 00 00 0a 61 62 00 00 00 00 01 0c 00 00 00 0a 78 79 00 00>, LIMIT 2, STOP true)
-> psp :: DiameterPopStorePushAVP;

psp[0] -> Print(out0, MAXLENGTH 200, CONTENTS HEX) -> Discard;
psp[1] -> Print(out1, MAXLENGTH 200, CONTENTS HEX) -> Discard;
