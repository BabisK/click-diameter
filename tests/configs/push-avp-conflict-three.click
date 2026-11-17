require(diameter);

// Three value sources: the error names the first conflicting pair in documented
// argument order, OCTETSTRING and UINT32, not the pair found last. Nothing may
// reach Print.
InfiniteSource(DATA \<01 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterPushAVP(CODE 264, OCTETSTRING "abc", UINT32 7, RANDHEXSTRING 4)
-> Print(push-avp-conflict-three, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
