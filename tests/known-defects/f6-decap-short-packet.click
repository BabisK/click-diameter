require(diameter);

// F-6: no length check. A 4-byte packet cannot hold the 20-byte header; Click
// logs "Packet::pull 20 > length 4" and the element forwards an empty packet.
// A correct build drops it.
InfiniteSource(DATA \<01 02 03 04>, LIMIT 1, STOP true)
-> DiameterDecap()
-> Print(decap, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
