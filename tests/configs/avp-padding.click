require(diameter);

// F-7: a 5-octet value plus the 8-octet header is 13 octets, so three zero
// octets pad the AVP to the 4-octet boundary RFC 6733 section 4.1 requires.
InfiniteSource(DATA \<61 62 63 64 65>, LIMIT 1, STOP true)
-> DiameterAvpEncap(CODE 264)
-> Print(avp-padding, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
