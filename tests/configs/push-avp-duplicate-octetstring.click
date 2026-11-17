require(diameter);

// A repeated keyword is Click's own argument syntax, not two value sources:
// Args keeps the last value, so this configuration has one source ("bc") and
// must keep configuring. The conflict check must not count a keyword twice.
InfiniteSource(DATA \<01 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterPushAVP(CODE 264, OCTETSTRING "a", OCTETSTRING "bc")
-> Print(push-avp-duplicate-octetstring, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
