require(diameter);

// V-8: padding the message tail satisfies the header's Length rule, not the AVP
// walk. The 5-octet payload becomes an 8-octet AVP-shaped tail whose fifth
// octet is data and whose length field reads zero, so DiameterPushAVP drops the
// well-formed-by-header frame with "AVP length below its header". This config
// pins the limitation the Encap page states.
InfiniteSource(DATA \<de ad be ef 00>, LIMIT 1, STOP true)
-> DiameterEncap(CODE 280, REQUEST true)
-> DiameterPushAVP(CODE 264, OCTETSTRING "abc")
-> Print(push-avp, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
