require(diameter);

// A well-formed vendor AVP: V set, 12-octet header, Length 17 (header plus the
// 5-octet value), Vendor-Id 42 and three zero pad octets. Decoding must pull
// the 12-octet header and the pad, leaving the value.
InfiniteSource(DATA \<00 00 01 08 80 00 00 11 00 00 00 2a 61 62 63 64 65 00 00 00>, LIMIT 1, STOP true)
-> DiameterAvpDecap()
-> Print(avp-decap-vendor, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
