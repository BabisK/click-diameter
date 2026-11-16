require(diameter);

// A 4-octet value makes the AVP exactly 12 octets, so it needs no padding.
InfiniteSource(DATA \<77 78 79 7a>, LIMIT 1, STOP true)
-> DiameterAvpEncap(CODE 264)
-> Print(avp-padding-none, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
