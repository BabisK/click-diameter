require(diameter);

// The AVP declares length 4, below its own 8-octet header. Decapsulating it
// would leave an empty packet, so it is dropped instead.
InfiniteSource(DATA \<00 00 01 08 00 00 00 04>, LIMIT 1, STOP true)
-> DiameterAvpDecap()
-> Print(avp-decap, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
