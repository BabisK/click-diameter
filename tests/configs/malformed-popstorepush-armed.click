require(diameter);

// The second pass is malformed while an AVP is armed. The valid 44-octet message
// stores its last AVP and emits 32 octets on port 0; Truncate cuts that back to
// 20 octets without fixing the header Length, and the loop feeds it in again.
// The guard must drop it with the stored AVP still armed, rather than appending
// at an offset past the packet.
InfiniteSource(DATA \<01 00 00 2c 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02 00 00 01 08 00 00 00 0a 61 62 00 00 00 00 01 0c 00 00 00 0a 78 79 00 00>, LIMIT 1, STOP true)
-> psp :: DiameterPopStorePushAVP;
psp[0] -> Truncate(LENGTH 20) -> psp;
psp[1] -> Discard;
