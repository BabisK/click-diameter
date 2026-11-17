require(diameter);

// A-6 as a message walker sees it: a well-framed 44-octet request whose first
// AVP is well formed and whose second is the 12-octet V=1, Vendor-Id=0 AVP.
// DiameterPopAVP inherits the reader check, which must run at every offset and
// drop the message on the second AVP.
InfiniteSource(DATA \<01 00 00 2c 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02 00 00 01 0a 00 00 00 0c 61 62 63 64 00 00 01 08 80 00 00 0c 00 00 00 00>, LIMIT 1, STOP true)
-> DiameterPopAVP()
-> Print(pop-avp, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
