require(diameter);

// DW-6/DW-8: a generated value above what the three-octet Length can carry is
// refused at configure time, so the run-time guard is exercised from a message
// that is already maximal. The first PushAVP fills a message to 16,777,212
// octets (0xFFFFFC); the second appends an 8-octet header-only AVP, which would
// reach 16,777,220 and is dropped instead of wrapping the Length.
InfiniteSource(DATA \<01 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterPushAVP(CODE 264, RANDHEXSTRING 16777184)
-> DiameterPushAVP(CODE 264, OCTETSTRING "")
-> Print(push-avp-length-overflow, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
