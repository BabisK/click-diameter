require(diameter);

// A-10 on the generator pair: the first generator used to win and the second
// was discarded with no diagnostic. At most one value source is allowed, so
// configuration fails and names both arguments. Nothing may reach Print.
InfiniteSource(DATA \<01 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterPushAVP(CODE 264, RANDNUMSTRING 4, RANDHEXSTRING 4)
-> Print(push-avp-conflict-randnumstring-randhexstring, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
