require(diameter);

// The message guard runs before the AVP is appended, so an E-bearing request is
// dropped here rather than grown into a larger invalid message.
InfiniteSource(DATA \<01 00 00 14 a0 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterPushAVP(CODE 264, OCTETSTRING "abc")
-> Print(push-avp, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
