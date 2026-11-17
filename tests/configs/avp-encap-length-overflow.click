require(diameter);

// DW-5: a 16,777,210-octet value plus the 8-octet AVP header exceeds the
// three-octet AVP Length. The envelope used to wrap its Length; now it is
// dropped with a warning before put().
InfiniteSource(LENGTH 16777210, LIMIT 1, STOP true)
-> DiameterAvpEncap(CODE 264)
-> Print(avp-encap-length-overflow, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
