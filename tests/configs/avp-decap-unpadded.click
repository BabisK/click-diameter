require(diameter);

// A standalone AVP from before the padding fix: 13 octets declaring length 13,
// with no padding at all. It is tolerated and decodes to its 5-octet value.
InfiniteSource(DATA \<00 00 01 08 00 00 00 0d 61 62 63 64 65>, LIMIT 1, STOP true)
-> DiameterAvpDecap()
-> Print(avp-decap, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
