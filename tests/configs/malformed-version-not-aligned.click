require(diameter);

// A-4 precedence: the frame is 25 octets and its Length field says 25, but its
// Version is 2. The Version test runs first, so the reported reason names the
// Version; the alignment test sits below it.
InfiniteSource(DATA \<02 00 00 19 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02 de ad be ef 00>, LIMIT 1, STOP true)
-> DiameterDecap()
-> Print(decap, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
