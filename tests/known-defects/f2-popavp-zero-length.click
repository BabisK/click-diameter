require(diameter);

// F-2: infinite loop. The trailing AVP declares length 0, so the scan that
// looks for the last AVP never advances and the process hangs instead of
// dropping the packet.
InfiniteSource(DATA \<01 00 00 20 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02 00 00 01 08 00 00 00 00 00 00 00 00 00 00 00 00>, LIMIT 1, STOP true)
-> DiameterPopAVP()
-> Print(pop-avp, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
