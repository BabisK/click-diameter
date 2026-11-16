require(diameter);

// F-1: a 44-octet two-AVP message whose last AVP is unpadded (length 10, body
// "xy"). Port 0 emits the 32-octet remainder; the self-loop feeds it back so
// port 1 re-appends the stored AVP and restores the original 44 octets, with
// the two padding octets zeroed. The body copy is narrowed to the unpadded
// length it allocates.
InfiniteSource(DATA \<01 00 00 2c 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02 00 00 01 08 00 00 00 0a 61 62 00 00 00 00 01 0c 00 00 00 0a 78 79 00 00>, LIMIT 1, STOP true)
-> psp :: DiameterPopStorePushAVP;
psp[0] -> Print(out0, MAXLENGTH 200, CONTENTS HEX) -> psp;
psp[1] -> Print(out1, MAXLENGTH 200, CONTENTS HEX) -> Discard;
