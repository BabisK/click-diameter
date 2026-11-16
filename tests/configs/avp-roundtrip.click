require(diameter);

// AVP wrap and unwrap must return the original 5-byte payload.
InfiniteSource(DATA \<61 62 63 64 65>, LIMIT 1, STOP true)
-> DiameterAvpEncap(CODE 264)
-> Print(avp-encap, MAXLENGTH 200, CONTENTS HEX)
-> DiameterAvpDecap()
-> Print(avp-decap, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
