require(diameter);

// Two string generators are two value sources, so the first must not silently
// win: configuration fails and names both. Nothing may reach Print.
InfiniteSource(DATA \<01 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterPushAVP(CODE 264, RANDALPHANUMSTRING 1, RANDALPHASTRING 1)
-> Print(push-avp-conflict-randalphanumstring-randalphastring, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
