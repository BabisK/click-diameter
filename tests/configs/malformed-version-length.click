require(diameter);

// A-5: both faults in one frame: Version 2 and a declared Length of 100 on 20
// octets. The Version reason is reported, because a frame that disagrees about
// the Version is not a Diameter message at any length.
InfiniteSource(DATA \<02 00 00 64 80 00 01 18 00 00 00 00 00 00 00 01 00 00 00 02>, LIMIT 1, STOP true)
-> DiameterDecap()
-> Print(decap, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
