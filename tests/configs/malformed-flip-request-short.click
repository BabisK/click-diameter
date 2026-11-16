require(diameter);

// A 4-octet packet cannot hold the 20-octet header the flip rewrites, so it is
// dropped instead of touching 16 octets outside the packet.
InfiniteSource(DATA \<01 02 03 04>, LIMIT 1, STOP true)
-> DiameterFlipRequest()
-> Print(flip-request, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
