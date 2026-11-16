require(diameter);

// F-2: the trailing AVP declares length 0. The scan must not loop forever; the
// message is dropped inside the timeout.
InfiniteSource(DATA \<01 00 00 20 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02 00 00 01 08 00 00 00 00 00 00 00 00>, LIMIT 1, STOP true)
-> DiameterPopAVP()
-> Print(pop-avp, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
