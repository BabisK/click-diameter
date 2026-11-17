require(diameter);

// Two InfiniteSource elements feed one DiameterPopStorePushAVP on two router
// threads, because StaticThreadSched puts the tasks on different threads and
// Click assigns every task to thread 0 unless a config says otherwise. Each
// packet carries a 44-octet message with two 12-octet AVPs whose values are the
// producer's four-octet marker, so an unarmed packet yields a 32-octet
// remainder on output 0 and an armed one a 56-octet message on output 1. The
// store is shared, so an output-1 frame may carry the other producer's marker;
// what a race breaks is the shape -- a frame whose Length or AVP Length no
// longer matches its octets, or a crash while one thread rewrites the header
// another is reading. The limit is 5000 so both producers run long
// enough to interleave, and only the first source stops the router, so the
// second keeps pushing until then. The test skips on a Click built without
// multithread support.
StaticThreadSched(a 0, b 1);
psp :: DiameterPopStorePushAVP;
psp[0] -> Print(smp-popstorepush-out0, MAXLENGTH 200, CONTENTS HEX) -> Discard;
psp[1] -> Print(smp-popstorepush-out1, MAXLENGTH 200, CONTENTS HEX) -> Discard;
a :: InfiniteSource(DATA \<01 00 00 2c 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02 00 00 01 09 40 00 00 0c 41 41 41 41 00 00 01 08 40 00 00 0c 41 41 41 41>, LIMIT 5000, STOP true) -> psp;
b :: InfiniteSource(DATA \<01 00 00 2c 80 00 01 18 00 00 00 00 00 00 00 03 00 00 00 04 00 00 01 09 40 00 00 0c 42 42 42 42 00 00 01 08 40 00 00 0c 42 42 42 42>, LIMIT 5000, STOP false) -> psp;
