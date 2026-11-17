require(diameter);

// Two producers of different payload lengths feed one DiameterEncap on two
// router threads, because Encap derives the message Length from the packet in
// hand: a cross-thread write between setLength and encode stamps one frame with
// the other packet's Length, and the printed octet count then contradicts the
// Length field. StaticThreadSched puts the tasks on different threads, since
// Click assigns every task to thread 0 unless a config says otherwise. The
// producers are InfiniteSource elements rather than DiameterRatedSource, whose
// generated message is always the same 20-octet header and takes no DATA
// argument, so no two payload lengths can come out of it. Only source4 stops the
// run; source8 keeps pushing until then, so an empty second shape means the two
// tasks did not interleave rather than that the run was too short. The count is
// high on purpose: the racy build produced 20 to 37 mismatched frames in roughly
// 9500, so a short run could pass it by luck. The test skips on a Click built
// without multithread support.
StaticThreadSched(source4 0, source8 1);
encap :: DiameterEncap(CODE 280, REQUEST true)
-> Print(smp-encap, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
source4 :: InfiniteSource(DATA \<de ad be ef>, LIMIT 5000, STOP true) -> encap;
source8 :: InfiniteSource(DATA \<de ad be ef 01 02 03 04>, LIMIT 5000, STOP false) -> encap;
