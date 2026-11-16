require(diameter);

// P is legal on either message type, so an answer carrying it is forwarded and
// only its length is validated here. A guard that dropped P fails this run.
InfiniteSource(DATA \<01 00 00 18 40 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02 de ad be ef>, LIMIT 1, STOP true)
-> DiameterDecap()
-> Print(decap-p-on-answer, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
