require(diameter);

// RFC 6733 header: version 1, length 20, flags R, code 280, appid 0, hop-by-hop 1, end-to-end 2.
// The no-value case with the 12-octet vendor header: an empty OCTETSTRING is
// the case RFC 6733 section 4.2 permits to stay at the header length, so the
// AVP Length is 12 and the frame 32 octets.
InfiniteSource(DATA \<01 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterPushAVP(CODE 264, VENDORSPEC true, VENDOR 42, OCTETSTRING "")
-> Print(push-avp-empty-vendor, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
