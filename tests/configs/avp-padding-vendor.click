require(diameter);

// VENDORID 42 selects the 12-octet header, so a 5-octet value gives 17 octets
// and three zero octets pad the AVP to 20. Flags are 80 (V set), Length 0x11.
InfiniteSource(DATA \<61 62 63 64 65>, LIMIT 1, STOP true)
-> DiameterAvpEncap(CODE 264, VENDORID 42)
-> Print(avp-padding-vendor, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
