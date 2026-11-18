require(diameter);

// Pins the unit the token bucket's timer is scheduled in. The burst is
// rate < 200 ? 2 : rate / 100, so RATE 1000 gives 10 tokens: the bucket is full
// once the first refill() runs and the first ten messages leave within a few
// nanoseconds of each other. The eleventh needs one more token, which takes one
// tick of the bucket's own unit, and the twelfth another. Both builds tick at
// 1 ms here -- jiffies at the default CLICK_HZ upstream, and microseconds in
// FastClick -- so the two deltas after the burst are 1 ms. A conversion that
// reads FastClick's microseconds as jiffies schedules the timer 1 s out, and the
// test sees that instead.
// --simtime makes the run deterministic; the timestamps are the packet
// annotation Print shows with TIMESTAMP true.
RandomSeed(SEED 12345);
DiameterRatedSource(CODE 280, REQUEST true, APPID 42, RATE 1000, LIMIT 12, STOP true)
-> Print(timing, TIMESTAMP true, MAXLENGTH 20, CONTENTS HEX)
-> Discard;
