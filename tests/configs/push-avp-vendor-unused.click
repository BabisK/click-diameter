require(diameter);

// VENDOR without VENDORSPEC: the Vendor-Id is ignored, so the AVP keeps the
// plain 8-octet header with V clear and the frame is the same 32 octets as
// push-avp.click.
InfiniteSource(DATA \<01 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterPushAVP(CODE 264, VENDOR 42, OCTETSTRING "abc")
-> Print(push-avp-vendor-unused, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
