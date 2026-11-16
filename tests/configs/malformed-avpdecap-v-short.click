require(diameter);

// F-6, AVP form: the V bit makes the header 12 octets, but the packet holds 8.
// The element reads the V bit from the 8-octet buffer and drops without ever
// decoding the 12-octet header.
InfiniteSource(DATA \<00 00 01 08 80 00 00 08>, LIMIT 1, STOP true)
-> DiameterAvpDecap()
-> Print(avp-decap, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
