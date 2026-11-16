require(diameter);

// E is legal on an answer, so a header-only message carrying it reaches the AVP
// walk and comes back unchanged. Only a Length or AVP fault would drop it.
InfiniteSource(DATA \<01 00 00 14 20 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterPopAVP()
-> Print(pop-avp-e, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
