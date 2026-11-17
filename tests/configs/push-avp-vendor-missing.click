require(diameter);

// A-1: RFC 6733 section 4.1.1 forbids Vendor-Id zero with V set, so VENDORSPEC
// true without VENDOR must fail configuration rather than emit a header whose
// Vendor-Id came from an uninitialised slot. Nothing may reach Print.
InfiniteSource(DATA \<01 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterPushAVP(CODE 264, VENDORSPEC true, OCTETSTRING "abc")
-> Print(push-avp-vendor-missing, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
