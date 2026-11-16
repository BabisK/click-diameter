require(diameter);

// F-4 end to end with the reader guards: Encap's Length covers the whole frame,
// so PushAVP accepts it and grows Length by the 16 padded octets of its AVP, and
// PopAVP strips that AVP again. The encapsulated payload is itself an AVP (code
// 264, no value) because the readers validate every octet after the header: a
// bare 4-octet payload such as deadbeef is a truncated AVP header and is
// dropped. Identifiers are random (F-11) and the test regexes them.
InfiniteSource(DATA \<00 00 01 08 00 00 00 08>, LIMIT 1, STOP true)
-> DiameterEncap(CODE 280, REQUEST true)
-> Print(encap, MAXLENGTH 200, CONTENTS HEX)
-> DiameterPushAVP(CODE 264, OCTETSTRING \<61 62 63 64 65>)
-> Print(push, MAXLENGTH 200, CONTENTS HEX)
-> DiameterPopAVP()
-> Print(pop, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
