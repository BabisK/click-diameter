require(diameter);

// F-3: the header claims length 100 for a 20-byte packet. The element must not
// append at offset 100; the message is dropped and no output line shows a
// declared length of 112.
InfiniteSource(DATA \<01 00 00 64 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterPushAVP(CODE 264, OCTETSTRING "abc")
-> Print(push-avp, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
