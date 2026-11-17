require(diameter);

// P is legal on either message type, so an answer carrying it is forwarded; the
// body is a valid 8-octet AVP because the reader validates the whole message,
// not only its header. A guard that dropped P fails this run.
InfiniteSource(DATA \<01 00 00 1c 40 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02 00 00 01 08 00 00 00 08>, LIMIT 1, STOP true)
-> DiameterDecap()
-> Print(decap-p-on-answer, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
