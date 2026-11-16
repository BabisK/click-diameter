require(diameter);

// A 28-octet message whose only AVP claims length 100. The padded AVP runs past
// the message end, so the scan never runs past the packet end.
InfiniteSource(DATA \<01 00 00 1c 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02 00 00 01 08 00 00 00 64>, LIMIT 1, STOP true)
-> DiameterPopAVP()
-> Print(pop-avp, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
