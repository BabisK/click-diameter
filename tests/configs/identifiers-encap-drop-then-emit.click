require(diameter);

// CAP-4: a packet dropped by the writer must not consume an identifier. A
// 5-octet payload is refused by DiameterEncap (it cannot be a sequence of
// padded AVPs), and the next packet is emitted through the same element, so the
// frame it carries must hold the seed's first two draws (16d5a847 3328a195).
// Advancing the counters before the drop guard moves them to the second pair.
// The two DelayUnqueue elements fix the order by simulated time, since Click
// schedules both sources in the same instant. The TimedSource is an empty
// stop timer: it ends the run after the delayed packets, because DelayUnqueue
// has no STOP of its own.
RandomSeed(SEED 12345);
qa :: Queue; qb :: Queue; m :: Queue;
dropped :: InfiniteSource(DATA \<de ad be ef 00>, LIMIT 1) -> qa;
emitted :: InfiniteSource(DATA \<de ad be ef>, LIMIT 1) -> qb;
qa -> DelayUnqueue(DELAY 0.001) -> m;
qb -> DelayUnqueue(DELAY 0.002) -> m;
stop :: TimedSource(INTERVAL 0.001, LIMIT 6, STOP true) -> Discard;
m -> DiameterEncap(CODE 280, REQUEST true)
-> Print(ids, MAXLENGTH 24, CONTENTS HEX)
-> Discard;
