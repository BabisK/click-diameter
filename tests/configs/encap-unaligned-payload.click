require(diameter);

// CAP-2/A-4: RFC 6733 section 3 defines the Message Length as the header plus
// the padded AVPs, so a body that is not on a 4-octet boundary cannot be a
// sequence of padded AVPs. The writer used to zero-pad the tail, which
// fabricated a plausible frame from five octets that are not an AVP; it now
// drops the packet with its own warning instead. The config sets no seed; the
// drop prints no frame, so no identifier is consumed.
InfiniteSource(DATA \<de ad be ef 00>, LIMIT 1, STOP true)
-> DiameterEncap(CODE 280, REQUEST true)
-> Print(encap-unaligned-payload, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
