require(diameter);

// The same two payload lengths into one DiameterAvpEncap on two router threads.
// AvpEncap derives the AVP Length and its padding from the packet in hand, so a
// cross-thread write between setLength and encode leaves the AVP Length
// disagreeing with the octets printed after it. StaticThreadSched splits the
// tasks, since Click assigns every task to thread 0 unless a config says
// otherwise; InfiniteSource is the producer because DiameterRatedSource always
// emits the same 20-octet header and takes no DATA argument. Only source4 stops
// the run, so source8 keeps pushing until then. The count is high on purpose:
// the racy build produced 20 to 37 mismatched frames in roughly 9500, so a short
// run could pass it by luck. The test skips on a Click built without multithread
// support.
StaticThreadSched(source4 0, source8 1);
encap :: DiameterAvpEncap(CODE 264)
-> Print(smp-avpencap, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
source4 :: InfiniteSource(DATA \<de ad be ef>, LIMIT 5000, STOP true) -> encap;
source8 :: InfiniteSource(DATA \<de ad be ef 01 02 03 04>, LIMIT 5000, STOP false) -> encap;
