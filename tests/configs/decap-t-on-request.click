require(diameter);

// RFC 6733 section 3 allows T on a request (it marks a retransmission), so a
// request carrying it is forwarded. The body is a valid 8-octet AVP because the
// reader validates the whole message, not only its header.
InfiniteSource(DATA \<01 00 00 1c 90 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02 00 00 01 08 00 00 00 08>, LIMIT 1, STOP true)
-> DiameterDecap()
-> Print(decap-t-on-request, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
