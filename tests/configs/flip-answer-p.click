require(diameter);

// An answer that illegally carries P flips to c0: R is set and P is left
// untouched, because RFC 6733 section 3 constrains the answers this element
// produces, not the request it derives from one.
InfiniteSource(DATA \<01 00 00 14 40 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterFlipRequest()
-> Print(flip-answer-p, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
