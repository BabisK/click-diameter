require(diameter);

// DW-4: a 16,777,200-octet payload pads to the same length, and 20 plus that
// exceeds the three-octet Message Length. The frame used to wrap its Length;
// now it is dropped with a warning before put(). The payload is generated
// because no config literal can carry 16 MB.
InfiniteSource(LENGTH 16777200, LIMIT 1, STOP true)
-> DiameterEncap(CODE 280, REQUEST true)
-> Print(encap-length-overflow, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
