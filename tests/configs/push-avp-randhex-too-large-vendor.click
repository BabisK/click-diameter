require(diameter);

// DW-6 with the vendor header: the 12-octet header leaves three fewer octets
// than the non-vendor case, so 16,777,181 characters are already too many and
// the limit is 16,777,180.
InfiniteSource(DATA \<01 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterPushAVP(CODE 264, VENDORSPEC true, VENDOR 42, RANDHEXSTRING 16777181)
-> Print(push-avp-randhex-too-large-vendor, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
