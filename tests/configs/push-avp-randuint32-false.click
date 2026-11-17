require(diameter);

// RANDUINT32 is false, its default, so it supplies nothing and OCTETSTRING is
// the single source: the frame is byte-identical to push-avp.click. Counting a
// present-but-false boolean as a source would make this fail configuration.
InfiniteSource(DATA \<01 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterPushAVP(CODE 264, RANDUINT32 false, OCTETSTRING "abc")
-> Print(push-avp-randuint32-false, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
