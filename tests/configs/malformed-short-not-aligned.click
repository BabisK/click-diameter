require(diameter);

// A-4 precedence: a 10-octet frame declares 25. The short-header guard runs
// before the alignment test, both to report the truncation and to keep the
// three-octet Length parse from reading past the packet.
InfiniteSource(DATA \<01 00 00 19 80 00 01 18 00 00>, LIMIT 1, STOP true)
-> DiameterDecap()
-> Print(decap, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
