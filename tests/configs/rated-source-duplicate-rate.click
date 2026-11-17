require(diameter);

// DW-2 with a positional argument: RATE is accepted positionally or by keyword,
// and a second RATE fails configuration naming the argument instead of keeping
// the last value.
DiameterRatedSource(CODE 280, REQUEST true, RATE 10, RATE 20, LIMIT 1, STOP true)
-> Print(rated-source-duplicate-rate, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
