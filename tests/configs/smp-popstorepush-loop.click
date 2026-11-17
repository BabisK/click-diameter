require(diameter);

// One 44-octet message is popped on thread 0. Its 32-octet remainder crosses a
// Queue, a push-to-pull boundary, and DelayUnqueue's task on thread 1 pushes it
// back into the same element, where the AVP stored on thread 0 must still be
// armed. A per-thread store would find nothing there, pop the remainder's only
// AVP instead, print a second 20-octet output-0 frame and never the restored
// 44-octet output-1 frame. The stop TimedSource sends no packet; its first tick
// ends the run after the delayed one has returned. The test skips on a Click
// built without multithread support.
StaticThreadSched(src 0, unq 1);
src :: InfiniteSource(DATA \<01 00 00 2c 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02 00 00 01 08 00 00 00 0a 61 62 00 00 00 00 01 0c 00 00 00 0a 78 79 00 00>, LIMIT 1) -> psp :: DiameterPopStorePushAVP;
psp[0] -> Print(out0, MAXLENGTH 200, CONTENTS HEX) -> Queue(10) -> unq :: DelayUnqueue(0.1) -> psp;
psp[1] -> Print(out1, MAXLENGTH 200, CONTENTS HEX) -> Discard;
stop :: TimedSource(INTERVAL 0.5, LIMIT 0, STOP true) -> Discard;
