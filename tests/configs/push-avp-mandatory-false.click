require(diameter);

// RFC 6733 header: version 1, length 20, flags R, code 280, appid 0, hop-by-hop 1, end-to-end 2.
// An explicit MANDATORY false still clears the M bit: the frame is the same 32
// octets as push-avp.click, with AVP flags 00.
InfiniteSource(DATA \<01 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterPushAVP(CODE 264, MANDATORY false, OCTETSTRING "abc")
-> Print(push-avp-mandatory-false, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
