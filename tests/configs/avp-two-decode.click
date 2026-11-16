require(diameter);

// F-7: 28 octets holding a padded 16-octet AVP (declared length 13) followed by
// a 12-octet AVP (length 12). The first decode must drop the first AVP and its
// padding, leaving the second AVP whole; the second decode yields its value.
InfiniteSource(DATA \<00 00 01 08 00 00 00 0d 61 62 63 64 65 00 00 00
                    00 00 01 0c 00 00 00 0c 77 78 79 7a>, LIMIT 1, STOP true)
-> DiameterAvpDecap()
-> Print(avp1, MAXLENGTH 200, CONTENTS HEX)
-> DiameterAvpDecap()
-> Print(avp2, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
