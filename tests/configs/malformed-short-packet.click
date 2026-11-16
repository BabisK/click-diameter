require(diameter);

// F-6: a 4-octet packet cannot hold the 20-octet header. The element drops it
// with one warning instead of pulling past the end and forwarding an empty
// packet.
InfiniteSource(DATA \<01 02 03 04>, LIMIT 1, STOP true)
-> DiameterDecap()
-> Print(decap, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
