require(diameter);

// DW-6: 16,777,185 hex characters plus the 8-octet AVP header and the 20-octet
// message header cannot fit 0xFFFFFF, so configuration fails instead of
// materialising the value on every packet and dropping it. The largest legal
// count is 16,777,184 (pinned by push-avp-length-max).
InfiniteSource(DATA \<01 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterPushAVP(CODE 264, RANDHEXSTRING 16777185)
-> Print(push-avp-randhex-too-large, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
