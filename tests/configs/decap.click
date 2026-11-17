require(diameter);

// The body is one 8-octet AVP (code 264, no value), the smallest a message can
// carry. DiameterDecap validates the whole message, so the body must be AVPs;
// stripping the 20-octet header leaves the eight AVP octets.
InfiniteSource(DATA \<01 00 00 1c 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02 00 00 01 08 00 00 00 08>, LIMIT 1, STOP true)
-> DiameterDecap()
-> Print(decap, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
