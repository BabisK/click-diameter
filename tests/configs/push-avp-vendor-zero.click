require(diameter);

// The same refusal as the absent VENDOR: an explicit VENDOR 0 is the value RFC
// 6733 section 4.1.1 forbids with V set, so configure must fail and nothing may
// reach Print.
InfiniteSource(DATA \<01 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterPushAVP(CODE 264, VENDORSPEC true, VENDOR 0, OCTETSTRING "abc")
-> Print(push-avp-vendor-zero, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
