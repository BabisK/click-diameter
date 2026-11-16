require(diameter);

// F-3: out-of-bounds write. The header claims length 100 for a 20-byte packet;
// the AVP is written at offset 100 and the declared length becomes 112, with no
// error. A correct build drops the packet or reports it instead.
InfiniteSource(DATA \<01 00 00 64 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterPushAVP(CODE 264, OCTETSTRING "abc")
-> Print(push-avp, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
