require(diameter);

// A-4 precedence: a 24-octet packet whose Length field says 25 carries both
// faults. The alignment test runs before the comparison, so the reported reason
// is the unaligned Length rather than the mismatch.
InfiniteSource(DATA \<01 00 00 19 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02 de ad be ef>, LIMIT 1, STOP true)
-> DiameterDecap()
-> Print(decap, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
