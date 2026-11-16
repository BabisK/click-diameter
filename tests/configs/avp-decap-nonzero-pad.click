require(diameter);

// The same padded AVP as avp-roundtrip, but its three pad octets are non-zero.
// RFC 6733 section 4 requires them to be zero; the decoder derives the padding
// size from Length alone, so a non-zero pad must not change the value.
InfiniteSource(DATA \<00 00 01 08 00 00 00 0d 61 62 63 64 65 ff ff ff>, LIMIT 1, STOP true)
-> DiameterAvpDecap()
-> Print(avp-decap-nonzero-pad, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
