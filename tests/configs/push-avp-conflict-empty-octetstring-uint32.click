require(diameter);

// An empty OCTETSTRING is a supplied source -- it asks for the no-value AVP --
// and UINT32 0 is a supplied value of four zero octets. They are two sources,
// so configuration fails even though both parsed values look empty; a presence
// test based on length() > 0 would configure here and discard one of them.
InfiniteSource(DATA \<01 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterPushAVP(CODE 268, OCTETSTRING "", UINT32 0)
-> Print(push-avp-conflict-empty-octetstring-uint32, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
