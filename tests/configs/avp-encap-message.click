require(diameter);

// A message whose only AVP came from DiameterAvpEncap must pass the message
// readers: the encoder pads the AVP, DiameterEncap frames it, and DiameterPopAVP
// walks the padded AVP and restores a header-only message. The config sets no
// seed, so the identifiers vary per run and the test regexes them.
InfiniteSource(DATA \<61 62 63 64 65>, LIMIT 1, STOP true)
-> DiameterAvpEncap(CODE 264)
-> DiameterEncap(CODE 280, REQUEST true)
-> Print(message, MAXLENGTH 200, CONTENTS HEX)
-> DiameterPopAVP()
-> Print(pop, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
