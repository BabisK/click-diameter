require(diameter);

// A-4 ordering: this 30-octet frame declares 30, so the header's alignment rule
// rejects it before the AVP walk. The last AVP also declares length 9 at offset
// 20, whose padded form (12) would run past the message, but that padded-bound
// guard is unreachable for an unaligned Length: the alignment reason is the one
// reported, which is what this config now pins.
InfiniteSource(DATA \<01 00 00 1e 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02 00 00 01 08 00 00 00 09 00 00>, LIMIT 1, STOP true)
-> DiameterPopAVP()
-> Print(pop-avp, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
