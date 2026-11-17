require(diameter);

// A zero-octet packet carries no Version octet at all. The one-octet guard keeps
// the Version test from reading past the buffer, so the packet is reported as a
// short header rather than a bad Version.
InfiniteSource(LENGTH 0, LIMIT 1, STOP true)
-> DiameterDecap()
-> Print(decap, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
