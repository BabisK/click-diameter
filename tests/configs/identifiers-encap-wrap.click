require(diameter);

// V-5: 2^20 + 1 messages cross the low-order 20-bit boundary of the End-to-End
// field once, so the high-order 12 bits must carry. One run is enough: the
// helper asserts COUNT distinct values in COUNT frames plus a span of COUNT - 1,
// so a masked low half repeats a value and widens the span. 240 000 messages
// never reach the boundary; this config is the only one that does.
RandomSeed(SEED 12345);
InfiniteSource(DATA \<de ad be ef>, LIMIT 1048577, STOP true)
-> DiameterEncap(CODE 280, REQUEST true)
-> Print(ids, MAXLENGTH 20, CONTENTS HEX)
-> Discard;
