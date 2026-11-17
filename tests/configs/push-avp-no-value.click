require(diameter);

// RFC 6733 header: version 1, length 20, flags R, code 280, appid 0, hop-by-hop 1, end-to-end 2.
// Neither a string nor a numeric source: the AVP is its 8-octet header alone,
// so the frame is 28 octets with AVP Length 8. This element has no dictionary,
// so the caller must not use this shape for a typed AVP such as Unsigned32.
InfiniteSource(DATA \<01 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterPushAVP(CODE 264)
-> Print(push-avp-no-value, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
