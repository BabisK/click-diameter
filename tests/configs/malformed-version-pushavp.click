require(diameter);

// A-5: the 20-octet frame declares Version 2, which RFC 6733 section 3 forbids.
// DiameterPushAVP must drop it instead of appending an AVP to a frame whose
// header it re-emits with the bogus Version intact.
InfiniteSource(DATA \<02 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterPushAVP(CODE 264, OCTETSTRING "abc")
-> Print(push-avp, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
