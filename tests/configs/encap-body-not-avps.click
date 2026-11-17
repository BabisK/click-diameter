require(diameter);

// V-8: a 4-octet body is on the 4-octet boundary, so DiameterEncap forwards it,
// but alignment is not validity: the body is not an AVP sequence, and
// DiameterPushAVP drops it with "packet shorter than the 8-octet AVP header".
// Alignment repairs the header's Length rule only, which is why the Encap page
// says the body is the caller's.
InfiniteSource(DATA \<de ad be ef>, LIMIT 1, STOP true)
-> DiameterEncap(CODE 280, REQUEST true)
-> DiameterPushAVP(CODE 264, OCTETSTRING "abc")
-> Print(push-avp, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
