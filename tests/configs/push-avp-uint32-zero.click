require(diameter);

// RFC 6733 header: version 1, length 20, flags R, code 280, appid 0, hop-by-hop 1, end-to-end 2.
// A-3: UINT32 0 is a 4-octet zero, so the AVP Length is 12, not 8 with no value
// (RFC 6733 section 4.2: Unsigned32 is Length 12).
InfiniteSource(DATA \<01 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterPushAVP(CODE 268, UINT32 0)
-> Print(push-avp-uint32-zero, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
