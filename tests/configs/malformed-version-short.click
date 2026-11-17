require(diameter);

// A-5: a 3-octet frame cannot hold a header, but its first octet already
// disagrees about the Version. The Version test runs before the short-header
// guard, so the reason names the Version rather than the truncation.
InfiniteSource(DATA \<02 00 00>, LIMIT 1, STOP true)
-> DiameterDecap()
-> Print(decap, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
