require(diameter);

// DW-2 with the keyword and its value split across a line, which Click still
// parses as one argument: the duplicate scan must end the keyword at any
// whitespace, not only at a space or tab. Before that fix this configuration
// passed and silently kept MANDATORY false.
InfiniteSource(DATA \<01 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterPushAVP(CODE 264, MANDATORY true, MANDATORY
false, OCTETSTRING "abc")
-> Print(push-avp-duplicate-wrapped, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
