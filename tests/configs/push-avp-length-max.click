require(diameter);

// The same append one 4-octet step shorter: 20 + 8 + 16,777,184 = 16,777,212
// octets (0xFFFFFC), the largest multiple of 4 at or below the three-octet
// Length ceiling (RFC 6733 section 3), so the AVP is appended rather than
// dropped. Print shows the message header and the start of the appended AVP:
// its 8-octet header (Code 0x00000108, Length 0xFFFFE8) and the first 8 value
// octets, rendered as 16 hex digits.
InfiniteSource(DATA \<01 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterPushAVP(CODE 264, RANDHEXSTRING 16777184)
-> Print(push-avp-length-max, MAXLENGTH 36, CONTENTS HEX)
-> Discard;
