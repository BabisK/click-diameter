require(diameter);

// A complete 8-octet AVP followed by three octets that cannot hold another AVP
// header. The walk stops with a drop instead of reading a truncated header.
InfiniteSource(DATA \<01 00 00 1f 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02 00 00 01 08 00 00 00 08 00 00 00>, LIMIT 1, STOP true)
-> DiameterPopAVP()
-> Print(pop-avp, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
