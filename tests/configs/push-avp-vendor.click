require(diameter);

// RFC 6733 header: version 1, length 20, flags R, code 280, appid 0, hop-by-hop 1, end-to-end 2.
// A vendor AVP: V set, 12-octet header, Length 15 (header plus "abc"), Vendor-Id 42
// and one zero pad octet. RFC 6733 section 4.1.1 requires a non-zero Vendor-Id.
InfiniteSource(DATA \<01 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterPushAVP(CODE 264, VENDORSPEC true, VENDOR 42, OCTETSTRING "abc")
-> Print(push-avp-vendor, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
