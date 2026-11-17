require(diameter);

// The same inclusive ceiling in DiameterRatedSource: 16777215 (0xFFFFFF) is a
// legal Command Code (RFC 6733 section 3), so the message carries ffffff. The
// config sets no seed, so the identifiers vary per run and the test regexes
// them.
DiameterRatedSource(CODE 16777215, REQUEST true, APPID 42, LIMIT 1, STOP true)
-> Print(rated-source-code-max, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
