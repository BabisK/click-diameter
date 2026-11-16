require(diameter);

// A 2-octet value makes the AVP 10 octets, so two zero octets pad it to 12.
// The Length field still counts only the header and the value.
InfiniteSource(DATA \<61 62>, LIMIT 1, STOP true)
-> DiameterAvpEncap(CODE 264)
-> Print(avp-padding-two, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
