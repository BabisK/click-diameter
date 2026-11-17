require(diameter);

// DW-4: an overflow drop keeps the stored AVP, so a later packet can carry it.
// Packet 1 arms the store with the largest legal AVP (16,777,184 value octets,
// AVP Length 0xffffe8, message Length 0xfffffc); packet 2 is a 28-octet message
// that cannot hold it (20 + the stored AVP would exceed 0xFFFFFF) and is
// dropped; packet 3 is a 20-octet message that can, and output 1 carries the
// stored AVP. A drop that clears the store fails the out1 line.
// The three DelayUnqueue elements fix the order by simulated time, since three
// push sources started in the same instant are otherwise scheduled by Click.
// The TimedSource is an empty stop timer: it ends the run after the delayed
// packets, because DelayUnqueue has no STOP of its own.
qa :: Queue; qb :: Queue; qc :: Queue;
psp :: DiameterPopStorePushAVP;
stop :: TimedSource(INTERVAL 0.001, LIMIT 8, STOP true) -> Discard;
big :: InfiniteSource(DATA \<01 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1)
-> DiameterPushAVP(CODE 264, RANDHEXSTRING 16777184) -> qa;
mid :: InfiniteSource(DATA \<01 00 00 1c 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02 00 00 01 08 00 00 00 08>, LIMIT 1) -> qb;
small :: InfiniteSource(DATA \<01 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1) -> qc;
qa -> DelayUnqueue(DELAY 0.001) -> psp;
qb -> DelayUnqueue(DELAY 0.002) -> psp;
qc -> DelayUnqueue(DELAY 0.003) -> psp;
psp[0] -> Print(out0, MAXLENGTH 40, CONTENTS HEX) -> Discard;
psp[1] -> Print(out1, MAXLENGTH 36, CONTENTS HEX) -> Discard;
