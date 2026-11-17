require(diameter);

// RFC 6733 header: version 1, length 20, flags R, code 280, appid 0, hop-by-hop 1, end-to-end 2.
// An empty OCTETSTRING is the case RFC 6733 section 4.2 permits to stay at AVP
// Length 8 (an OctetString value of no octets is 8 long). This must not move to
// four octets when the numeric sources start emitting a zero.
InfiniteSource(DATA \<01 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterPushAVP(CODE 264, OCTETSTRING "")
-> Print(push-avp-empty, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
