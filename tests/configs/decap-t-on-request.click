require(diameter);

// RFC 6733 section 3 allows T on a request (it marks a retransmission), so a
// request carrying it is forwarded. Only its Length is validated here.
InfiniteSource(DATA \<01 00 00 18 90 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02 de ad be ef>, LIMIT 1, STOP true)
-> DiameterDecap()
-> Print(decap-t-on-request, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
