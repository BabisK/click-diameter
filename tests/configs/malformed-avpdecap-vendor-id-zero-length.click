require(diameter);

// The Vendor-Id test follows the Length checks: this 12-octet AVP has V set,
// Vendor-Id 0 and a Length of 8, below its own 12-octet header. The structural
// fault must win with "AVP length below its header", not the Vendor-Id reason.
InfiniteSource(DATA \<00 00 01 08 80 00 00 08 00 00 00 00>, LIMIT 1, STOP true)
-> DiameterAvpDecap()
-> Print(avp-decap, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
