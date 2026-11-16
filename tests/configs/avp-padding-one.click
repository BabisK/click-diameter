require(diameter);

// A 3-octet value makes the AVP 11 octets, so exactly one zero octet pads it to
// 12. The Length field still counts only the header and the value.
InfiniteSource(DATA \<61 62 63>, LIMIT 1, STOP true)
-> DiameterAvpEncap(CODE 264)
-> Print(avp-padding-one, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
