require(diameter);

// Two DiameterRatedSource elements feed one DiameterPushAVP. StaticThreadSched
// puts the sources on two different router threads, because Click assigns every
// task to thread 0 unless a config says otherwise; with both threads pushing at
// once, the append must keep no per-packet state in the element. RATE keeps the
// token bucket full, so the packets leave back to back instead of at the default
// ten per second, which would put the two threads a tenth of a second apart. The
// limit is 1000 rather than a handful: a short run can have the first source
// reach its limit before the second is scheduled at all, which on a one-core
// machine produced 50 frames from one source and none from the other. Only
// source1 stops the router, so source2 keeps pushing until then. Each source emits header-only requests (Length 20) with its own Command
// Code, so every frame is the 20-octet message header, the 8-octet AVP header
// and an 8-octet generated value: 36 octets, message Length 0x24, AVP Length
// 0x10, and a code that says which source produced it. This is a shape check,
// not a race detector: the appended AVP Length comes from configuration, so no
// interleaving can change it. The test skips on a Click built without
// multithread support.
StaticThreadSched(source1 0, source2 1);
push :: DiameterPushAVP(CODE 264, RANDHEXSTRING 8)
-> Print(smp-push-avp, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
source1 :: DiameterRatedSource(CODE 280, REQUEST true, RATE 100000, LIMIT 1000, STOP true) -> push;
source2 :: DiameterRatedSource(CODE 281, REQUEST true, RATE 100000, LIMIT 1000, STOP false) -> push;
