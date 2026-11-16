require(diameter);

// F-4: an empty packet still gets a full 20-octet header -- version 1, Length 20,
// no payload. Identifiers are random (F-11) and the test regexes them.
InfiniteSource(LENGTH 0, LIMIT 1, STOP true)
-> DiameterEncap(CODE 280, REQUEST true)
-> Print(encap-empty, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
