require(diameter);

// DW-5's inclusive ceiling: a 16,777,207-octet value plus the 8-octet AVP header
// is exactly 0xFFFFFF, the largest three-octet AVP Length (RFC 6733 section
// 4.1), so the AVP is emitted with Length ffffff and padded to 16,777,216
// octets. A guard written as >= rejects this config.
InfiniteSource(LENGTH 16777207, LIMIT 1, STOP true)
-> DiameterAvpEncap(CODE 264)
-> Print(avp-encap-length-max, MAXLENGTH 8, CONTENTS HEX)
-> Discard;
