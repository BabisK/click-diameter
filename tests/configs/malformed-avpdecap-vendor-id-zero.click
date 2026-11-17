require(diameter);

// A-6, standalone AVP form: V is set, the 12-octet header is present and the
// Length agrees, but the Vendor-Id is zero. RFC 6733 section 4.1.1 forbids that
// combination, so DiameterAvpDecap must drop it without forwarding a value.
InfiniteSource(DATA \<00 00 01 08 80 00 00 0c 00 00 00 00>, LIMIT 1, STOP true)
-> DiameterAvpDecap()
-> Print(avp-decap, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
