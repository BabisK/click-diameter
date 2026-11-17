require(diameter);

// A-4: the frame the pre-change DiameterEncap emitted for a 5-octet payload -- 25
// octets whose Length field says 25. RFC 6733 section 3 makes the Message Length
// a multiple of 4, so a reader rejects it before comparing it to the packet and
// forwards no payload.
InfiniteSource(DATA \<01 00 00 19 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02 de ad be ef 00>, LIMIT 1, STOP true)
-> DiameterDecap()
-> Print(decap, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
