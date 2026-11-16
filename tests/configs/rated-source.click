require(diameter);

// A generated message is a bare 20-octet header: version 1, Length 20, code 280
// (0x118), App-Id 42 (0x2a), and flags initialized to R alone. Which flags a
// request may carry is F-5's story; this pins the initialization. The config
// sets no seed, so the identifiers vary per run and the test regexes them.
DiameterRatedSource(CODE 280, REQUEST true, APPID 42, LIMIT 1, STOP true)
-> Print(rated-source, MAXLENGTH 200, CONTENTS HEX)
-> Discard;
