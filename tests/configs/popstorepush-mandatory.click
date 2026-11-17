require(diameter);

// DW-1: a received AVP with the M bit set must survive DiameterPopStorePushAVP's
// decode and re-encode. The same 32-octet frame is sent twice: the first pass
// pops the AVP (output 0), the second pushes the stored AVP back (output 1), so
// output 1 carries the decoded AVP again with flags 40.
InfiniteSource(DATA \<01 00 00 20 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02 00 00 01 08 40 00 00 0b 61 62 63 00>, LIMIT 2, STOP true)
-> psp :: DiameterPopStorePushAVP;
psp[0] -> Print(out0, MAXLENGTH 200, CONTENTS HEX) -> Discard;
psp[1] -> Print(out1, MAXLENGTH 200, CONTENTS HEX) -> Discard;
