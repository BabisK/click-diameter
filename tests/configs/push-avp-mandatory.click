require(diameter);

// RFC 6733 header: version 1, length 20, flags R, code 280, appid 0, hop-by-hop 1, end-to-end 2.
// MANDATORY sets the M bit (A-2): the AVP flags octet is 40 rather than 00.
InfiniteSource(DATA \<01 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterPushAVP(CODE 264, MANDATORY true, OCTETSTRING "abc")
-> Print(push-avp-mandatory, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
