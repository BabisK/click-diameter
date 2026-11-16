require(diameter);

// F-6, AVP form: 6 octets cannot hold the 8-octet AVP header. The element
// drops the packet instead of pulling past the end.
InfiniteSource(DATA \<00 00 01 08 00 00>, LIMIT 1, STOP true)
-> DiameterAvpDecap()
-> Print(avp-decap, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
