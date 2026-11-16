require(diameter);

// The same E-on-request frame through a message reader: DiameterPopAVP shares
// diameter_check_header, so the flag reason wins before the AVP walk.
InfiniteSource(DATA \<01 00 00 18 a0 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02 de ad be ef>, LIMIT 1, STOP true)
-> DiameterPopAVP()
-> Print(pop-avp, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
