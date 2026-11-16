require(diameter);

// The last AVP declares length 9 at offset 20, so its unpadded form fits in the
// 30-octet message but its padded form (12) runs past the end. Popping twelve
// octets would take more than the message holds, so the packet is dropped.
InfiniteSource(DATA \<01 00 00 1e 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02 00 00 01 08 00 00 00 09 00 00>, LIMIT 1, STOP true)
-> DiameterPopAVP()
-> Print(pop-avp, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
