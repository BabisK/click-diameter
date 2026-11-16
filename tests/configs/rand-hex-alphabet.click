require(diameter);

// F-9: 10,000 characters, every one of them a hex digit 0-9 or A-F. AVP Length
// 8 + 10000 = 10008 (0x2718), no padding, so the message is 10028 octets.
InfiniteSource(DATA \<01 00 00 14 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterPushAVP(CODE 264, RANDHEXSTRING 10000)
-> Print(rand-hex-alphabet, MAXLENGTH 20000, CONTENTS HEX)
-> Discard;
