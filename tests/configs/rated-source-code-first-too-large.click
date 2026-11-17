require(diameter);

// The same first illegal Code in the second writer: 16777216 (0x1000000) does
// not fit the three-octet Command Code field (RFC 6733 section 3), so
// DiameterRatedSource must refuse it and nothing may reach Print.
DiameterRatedSource(CODE 16777216, REQUEST true, LIMIT 1, STOP true)
-> Print(rated-source-code-first-too-large, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
