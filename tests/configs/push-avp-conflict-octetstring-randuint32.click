require(diameter);

// RANDUINT32 is a source when true, so it conflicts with OCTETSTRING and the
// draw must not silently replace the literal value. Nothing may reach Print.
InfiniteSource(DATA \<01 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterPushAVP(CODE 264, OCTETSTRING "abc", RANDUINT32 true)
-> Print(push-avp-conflict-octetstring-randuint32, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
