require(diameter);

// DW-2: a repeated keyword fails configuration naming it. Click's Args would
// keep the last value ("bc") and silently discard "a"; the package now rejects
// the repeat rather than resolving it.
InfiniteSource(DATA \<01 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterPushAVP(CODE 264, OCTETSTRING "a", OCTETSTRING "bc")
-> Print(push-avp-duplicate-octetstring, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
