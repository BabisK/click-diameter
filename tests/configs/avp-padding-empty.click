require(diameter);

// An empty value makes the AVP exactly its 8-octet header, so no padding is
// added and the Length field is 8.
InfiniteSource(LENGTH 0, LIMIT 1, STOP true)
-> DiameterAvpEncap(CODE 264)
-> Print(avp-padding-empty, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
