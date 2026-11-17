require(diameter);

// A-10: OCTETSTRING and UINT32 used to resolve by if/else order, so this
// configuration emitted "abc" and discarded the 7 that decides the value type.
// At most one value source is allowed, so configuration fails and names both
// arguments. Nothing may reach Print.
InfiniteSource(DATA \<01 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterPushAVP(CODE 264, OCTETSTRING "abc", UINT32 7)
-> Print(push-avp-conflict-octetstring-uint32, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
