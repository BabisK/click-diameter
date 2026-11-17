require(diameter);

// A-4's rewriter half: the same 25-octet frame whose Length field says 25 is
// dropped by DiameterPushAVP instead of being appended to and re-emitted with an
// unaligned Length.
InfiniteSource(DATA \<01 00 00 19 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02 de ad be ef 00>, LIMIT 1, STOP true)
-> DiameterPushAVP(CODE 264, OCTETSTRING "x")
-> Print(push-avp, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
