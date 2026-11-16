require(diameter);

// The header declares Length 20 but the packet holds 24 octets. A Length below
// the packet length is as untrustworthy as one above it, so the message is
// dropped instead of appending at an offset that hides trailing bytes.
InfiniteSource(DATA \<01 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02 de ad be ef>, LIMIT 1, STOP true)
-> DiameterPushAVP(CODE 264, OCTETSTRING "abc")
-> Print(push-avp, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
