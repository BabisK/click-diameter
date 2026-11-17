require(diameter);

// DW-3: SEED 808357014 makes Click's first click_random() draw zero, so the
// RANDUINT32 value is a four-octet zero at AVP Length 12 rather than an empty
// AVP. The seed pins glibc's random() for SEED, which is the generator Click's
// RandomSeed drives.
RandomSeed(SEED 808357014);
InfiniteSource(DATA \<01 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterPushAVP(CODE 268, RANDUINT32 true)
-> Print(push-avp-randuint32-zero, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
