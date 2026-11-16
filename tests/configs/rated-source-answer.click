require(diameter);

// The answer side of F-5: the element never assigns proxiable, error or
// retransmitted, and the header constructor starts them clear, so a generated
// answer shows flags 00. Identifiers are random (F-11) and the test regexes
// them.
DiameterRatedSource(CODE 280, REQUEST false, APPID 42, LIMIT 1, STOP true)
-> Print(rated-source-answer, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
