require(diameter);

// RFC 6733 header: version 1, length 20, flags R, code 280, appid 0, hop-by-hop 1, end-to-end 2.
// A mandatory vendor AVP: M is 0x40 and V is 0x80, so the flags octet is c0.
// The 12-octet header carries Vendor-Id 42; the value "abc" is padded by one
// zero octet to 36 octets in total.
InfiniteSource(DATA \<01 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterPushAVP(CODE 264, MANDATORY true, VENDORSPEC true, VENDOR 42, OCTETSTRING "abc")
-> Print(push-avp-mandatory-vendor, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
