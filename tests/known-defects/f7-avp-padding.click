require(diameter);

// F-7: no 4-octet padding. An 8-byte header plus a 5-byte payload gives 13
// bytes; RFC 6733 section 4.1 requires 16, so the following AVP would be read
// 3 bytes early.
InfiniteSource(DATA \<61 62 63 64 65>, LIMIT 1, STOP true)
-> DiameterAvpEncap(CODE 264)
-> Print(avp-encap, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
