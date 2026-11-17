require(diameter);

// The shared AVP check reaches DiameterPushAVP's message validation too: a
// well-framed 32-octet request carrying a V=1, Vendor-Id=0 AVP is dropped
// before anything is appended.
InfiniteSource(DATA \<01 00 00 20 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02 00 00 01 08 80 00 00 0c 00 00 00 00>, LIMIT 1, STOP true)
-> DiameterPushAVP(CODE 264)
-> Print(push-avp, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
