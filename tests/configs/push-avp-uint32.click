require(diameter);

// RFC 6733 header: version 1, length 20, flags R, code 280, appid 0, hop-by-hop 1, end-to-end 2.
// The deterministic numeric value the argument surface promises: UINT32 2001 is
// a 4-octet big-endian number, so the AVP Length is 12 and the value 000007d1.
InfiniteSource(DATA \<01 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterPushAVP(CODE 268, UINT32 2001)
-> Print(push-avp-uint32, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
