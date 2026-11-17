require(diameter);

// A-9: 20 header octets plus an 8-octet AVP header and a 16,777,188-octet value
// is 16,777,216 octets, one octet past the three-octet Length field (RFC 6733
// section 3). The AVP would wrap Length to 0x000000, so the packet is dropped
// with its own warning and nothing reaches Print. The value is generated
// because no config literal can carry 16 MB.
InfiniteSource(DATA \<01 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterPushAVP(CODE 264, RANDHEXSTRING 16777188)
-> Print(push-avp-length-overflow, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
