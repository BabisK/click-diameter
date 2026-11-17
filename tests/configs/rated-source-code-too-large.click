require(diameter);

// A-9 in the second writer: DiameterRatedSource shares the truncation path
// through DiameterHeader::setCode(), so 16777496 must fail configuration here
// too and nothing may reach Print.
DiameterRatedSource(CODE 16777496, REQUEST true, LIMIT 1, STOP true)
-> Print(rated-source-code-too-large, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
