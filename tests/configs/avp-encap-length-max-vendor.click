require(diameter);

// The same inclusive ceiling with the 12-octet vendor header: 16,777,203 value
// octets plus that header is 0xFFFFFF, so the AVP is emitted with Length
// ffffff and Vendor-Id 42. The vendor header leaves four fewer octets than the
// non-vendor case, which is why its value limit is lower.
InfiniteSource(LENGTH 16777203, LIMIT 1, STOP true)
-> DiameterAvpEncap(CODE 264, VENDORID 42)
-> Print(avp-encap-length-max-vendor, MAXLENGTH 12, CONTENTS HEX)
-> Discard;
