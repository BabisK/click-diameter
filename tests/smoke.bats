#!/usr/bin/env bats
#
# Byte-level assertions over the smoke configs in configs/.
#
#   bats --tap tests                              # click from PATH
#   CLICK=~/click/bin/click bats --tap tests      # explicit binary
#
# Requires bats-core. Every expectation below pins the bytes the element emits
# today, so a change in them fails the run. Octets that are deliberately random
# -- the hbh/e2e identifiers of F-11 -- are matched with a regex instead of
# compared exactly, and the encap test runs its config a second time to check
# that every other field comes back byte for byte. The rand-* tests pin the
# length and the alphabet of each DiameterPushAVP generator. The avp-padding*
# and avp-decap-* tests pin the 4-octet AVP alignment of RFC 6733 section 4.1
# and the rule that the decoder derives padding from Length alone. The
# malformed-* tests assert the drop path instead: exit 0, one warning naming the
# element and reason, and no Print line. The two configs the package refuses --
# ERROR on a request and PROXIABLE on an answer -- assert the configure path:
# Click's whole configure-failure output and no Print line.

click=${CLICK:-click}
click_timeout=${CLICK_TIMEOUT:-10}

# run_click CONFIG -- run configs/CONFIG under a timeout, capturing the output.
run_click() {
	if command -v timeout >/dev/null 2>&1; then
		run timeout "$click_timeout" "$click" "$BATS_TEST_DIRNAME/configs/$1"
	else
		run "$click" "$BATS_TEST_DIRNAME/configs/$1"
	fi
}

# expect OUTPUT -- the whole captured output, byte for byte.
expect() {
	[ "$output" = "$1" ] || { echo "expected: $1"; return 1; }
}

# expect_drop ELEMENT REASON -- exit 0, exactly one warning naming the element
# and the reason, and no packet that reached Print. A forwarded malformed
# packet or a silent drop fails the run.
expect_drop() {
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	local warning="$1: dropping malformed packet: $2"
	[ "$output" = "$warning" ] || { echo "expected: $warning"; return 1; }
}

# expect_configure_failure CONFIG MESSAGE -- a non-zero exit and Click's whole
# configure-failure output for that config: the config path and line, the
# element being configured, the named error, and the closing line. A crash, a
# second error, an extra warning or a packet that reached Print fails the run.
expect_configure_failure() {
	[ "$status" -ne 0 ] || { echo "expected a configure failure, click exit $status"; return 1; }
	local expected="$BATS_TEST_DIRNAME/configs/$1":*": While configuring 'DiameterEncap@2 :: DiameterEncap':"$'\n'"  $2"$'\n'"Router could not be initialized!"
	[[ "$output" == $expected ]] || { echo "expected: $expected"; echo "got: $output"; return 1; }
}

@test "push-avp: appending an AVP, header length updated" {
	run_click push-avp.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	expect 'push-avp:   32 | 01000020 80000118 00000000 00000001 00000002 00000108 0000000b 61626300'
}

@test "push-avp-rand: generated value, 8 characters" {
	run_click push-avp-rand.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	local generated='^push-avp-rand: +36 \| 01000024 80000118 00000000 00000001 00000002 00000108 00000010 (3[0-9]|4[1-9a-f]|5[0-9a]|6[1-9a-f]|7[0-9a]){4} (3[0-9]|4[1-9a-f]|5[0-9a]|6[1-9a-f]|7[0-9a]){4}$'
	[[ "$output" =~ $generated ]] || { echo "expected: 36 bytes, AVP length 16, 8 generated alphanumeric characters"; return 1; }
}

@test "rand-alphanum-one: one generated character, AVP Length 9" {
	run_click rand-alphanum-one.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# F-8: a count of 1 used to fall through every branch and emit an empty
	# 8-octet AVP. The one character is followed by three zero pad octets.
	local expected='^rand-alphanum-one: +32 \| 01000020 80000118 00000000 00000001 00000002 00000108 00000009 (3[0-9]|4[1-9a-f]|5[0-9a]|6[1-9a-f]|7[0-9a])000000$'
	[[ "$output" =~ $expected ]] || { echo "expected: 32 octets, AVP Length 9, one alphanumeric character and three zero pad octets"; return 1; }
}

@test "rand-hex-one: one hex character, never an empty AVP" {
	run_click rand-hex-one.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# F-8 on the hex generator: AVP Length 9, not an 8-octet header-only AVP.
	local expected='^rand-hex-one: +32 \| 01000020 80000118 00000000 00000001 00000002 00000108 00000009 (3[0-9]|4[1-6])000000$'
	[[ "$output" =~ $expected ]] || { echo "expected: 32 octets, AVP Length 9, one hex character and three zero pad octets"; return 1; }
}

@test "rand-hex-alphabet: 10,000 generated characters, all of them hex" {
	run_click rand-hex-alphabet.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# F-9: Print renders the value as hex octets, so a literal G appears as 47
	# and a text search for G would prove nothing. Decode the 10,000 value octets,
	# check each one against 0-9 / A-F, and confirm all 16 symbols appear. The
	# 10 kB append makes Click print one advisory; any other output is a failure.
	local printed others
	printed=$(grep '^rand-hex-alphabet:' <<<"$output")
	others=$(grep -v '^rand-hex-alphabet:' <<<"$output" | grep -v '^expensive Packet::put' || true)
	[ -z "$others" ] || { echo "unexpected output beside the Print line: $others"; return 1; }
	local header='^rand-hex-alphabet: +10028 \| 0100272c 80000118 00000000 00000001 00000002 00000108 00002718 '
	[[ "$printed" =~ $header ]] || { echo "expected: 10028 octets, AVP Length 10008, message Length 10028"; return 1; }
	local octets
	octets=$(tr -d ' \n' <<<"${printed#*00002718 }")
	[ "${#octets}" -eq 20000 ] || { echo "expected 10,000 value octets, got ${#octets} hex digits"; return 1; }
	local bad
	bad=$(awk -v v="$octets" 'BEGIN {
		n = split("0:30 1:31 2:32 3:33 4:34 5:35 6:36 7:37 8:38 9:39 A:41 B:42 C:43 D:44 E:45 F:46", tbl, " ")
		for (i = 1; i <= n; i++) {
			split(tbl[i], kv, ":")
			pair[kv[1]] = kv[2]
		}
		for (i = 1; i <= length(v); i += 2) {
			o = substr(v, i, 2)
			if (o !~ /^(3[0-9]|4[1-6])$/) { print "invalid octet " o; exit }
			seen[o] = 1
		}
		for (i = 1; i <= n; i++) {
			split(tbl[i], kv, ":")
			if (!(pair[kv[1]] in seen)) { print "missing symbol " kv[1]; exit }
		}
	}')
	[ -z "$bad" ] || { echo "generated value is not 0-9/A-F: $bad"; return 1; }
}

@test "rand-num-four: four generated digits, AVP Length 12" {
	run_click rand-num-four.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	local expected='^rand-num-four: +32 \| 01000020 80000118 00000000 00000001 00000002 00000108 0000000c (3[0-9]){4}$'
	[[ "$output" =~ $expected ]] || { echo "expected: 32 octets, AVP Length 12, four digits from 0-9"; return 1; }
}

@test "rand-alpha-four: four generated letters, AVP Length 12" {
	run_click rand-alpha-four.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	local expected='^rand-alpha-four: +32 \| 01000020 80000118 00000000 00000001 00000002 00000108 0000000c (4[1-9a-f]|5[0-9a]|6[1-9a-f]|7[0-9a]){4}$'
	[[ "$output" =~ $expected ]] || { echo "expected: 32 octets, AVP Length 12, four letters from A-Z/a-z"; return 1; }
}

@test "pop-avp: removing the last AVP from a two-AVP message" {
	run_click pop-avp.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	expect 'pop-avp:   32 | 01000020 80000118 00000000 00000001 00000002 00000108 0000000a 61620000'
}

@test "avp-roundtrip: DiameterAvpEncap then DiameterAvpDecap returns the payload" {
	run_click avp-roundtrip.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# 8-octet header plus the 5-octet value is 13, padded to 16 octets; the
	# decoder strips the pad, so the value comes back byte for byte (F-7).
	expect $'avp-encap:   16 | 00000108 0000000d 61626364 65000000\navp-decap:    5 | 61626364 65'
}

@test "avp-padding: a 5-octet value is padded to a 16-octet AVP" {
	run_click avp-padding.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	expect 'avp-padding:   16 | 00000108 0000000d 61626364 65000000'
}

@test "avp-padding-two: a 2-octet value gets two zero pad octets" {
	run_click avp-padding-two.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	expect 'avp-padding-two:   12 | 00000108 0000000a 61620000'
}

@test "avp-padding-none: a 4-octet value needs no padding" {
	run_click avp-padding-none.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	expect 'avp-padding-none:   12 | 00000108 0000000c 7778797a'
}

@test "avp-padding-vendor: the 12-octet vendor header is padded too" {
	run_click avp-padding-vendor.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	expect 'avp-padding-vendor:   20 | 00000108 80000011 0000002a 61626364 65000000'
}

@test "avp-two-decode: consecutive padded AVPs decode at the right offsets" {
	run_click avp-two-decode.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	expect $'avp1:   12 | 0000010c 0000000c 7778797a\navp2:    4 | 7778797a'
}

@test "avp-decap-unpadded: a legacy standalone unpadded AVP still decodes" {
	run_click avp-decap-unpadded.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	expect 'avp-decap:    5 | 61626364 65'
}

@test "avp-padding-one: a 3-octet value gets one zero pad octet" {
	run_click avp-padding-one.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	expect 'avp-padding-one:   12 | 00000108 0000000b 61626300'
}

@test "avp-padding-empty: an empty value is an 8-octet AVP with no padding" {
	run_click avp-padding-empty.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	expect 'avp-padding-empty:    8 | 00000108 00000008'
}

@test "avp-decap-vendor: a 20-octet vendor AVP decodes to its value" {
	run_click avp-decap-vendor.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	expect 'avp-decap-vendor:    5 | 61626364 65'
}

@test "avp-decap-nonzero-pad: the pad content does not affect the decode" {
	run_click avp-decap-nonzero-pad.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	expect 'avp-decap-nonzero-pad:    5 | 61626364 65'
}

@test "avp-encap-message: a message built from AvpEncap passes the message readers" {
	run_click avp-encap-message.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# The encoder's padded AVP is accepted by PopAVP, which walks the padded
	# AVP and restores a header-only 20-octet message. Identifiers are random.
	local expected='^message: +36 \| 01000024 80000118 00000000 [0-9a-f]{8} [0-9a-f]{8} 00000108 0000000d 61626364 65000000
pop: +20 \| 01000014 80000118 00000000 [0-9a-f]{8} [0-9a-f]{8}$'
	[[ "$output" =~ $expected ]] || { echo "expected: the 36-octet message, then the 20-octet header-only frame"; return 1; }
}

@test "flip-request: request bit cleared on a request" {
	run_click flip-request.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	expect 'flip-request:   20 | 01000014 00000118 00000000 00000001 00000002'
}

@test "flip-request-p: a proxiable request flips to flags 00, P cleared with R" {
	run_click flip-request-p.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	expect 'flip-request-p:   20 | 01000014 00000118 00000000 00000001 00000002'
}

@test "flip-answer: flipping an answer sets R, flags 00 to 80" {
	run_click flip-answer.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	expect 'flip-answer:   20 | 01000014 80000118 00000000 00000001 00000002'
}

@test "flip-answer-p: a flipped answer becomes a request and keeps P, flags 40 to c0" {
	run_click flip-answer-p.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	expect 'flip-answer-p:   20 | 01000014 c0000118 00000000 00000001 00000002'
}

@test "decap: stripping the 20-byte header leaves the payload" {
	run_click decap.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	expect 'decap:    4 | deadbeef'
}

@test "encap: version 1, Length counts the header plus the payload" {
	run_click encap.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# F-4: version, Length, flags, code and App-Id are asserted exactly; only the
	# random hbh/e2e of F-11 are regexed.
	local expected='^encap: +24 \| 01000018 80000118 00000000 [0-9a-f]{8} [0-9a-f]{8} deadbeef$'
	[[ "$output" =~ $expected ]] || { echo "expected: 24 octets, version 1, Length 24, then the payload"; return 1; }
	# REPEATED_RUNS: a second run must agree on every field that is not random.
	local deterministic='{ print $1, $2, $3, $4, $5, $6 }'
	local first_run
	first_run=$(awk "$deterministic" <<<"$output")
	run_click encap.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	[ "$(awk "$deterministic" <<<"$output")" = "$first_run" ] || { echo "expected: version, Length, flags, code and App-Id identical across runs"; return 1; }
}

@test "encap-empty: a zero-octet packet gets a 20-octet header" {
	run_click encap-empty.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	local expected='^encap-empty: +20 \| 01000014 80000118 00000000 [0-9a-f]{8} [0-9a-f]{8}$'
	[[ "$output" =~ $expected ]] || { echo "expected: 20 octets, version 1, Length 20, no payload"; return 1; }
}

@test "encap-decap: the encapsulated payload survives Decap without a drop" {
	run_click encap-decap.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# Only the two Print lines: any drop warning fails the regex.
	local expected='^encap: +24 \| 01000018 80000118 00000000 [0-9a-f]{8} [0-9a-f]{8} deadbeef
decap: +4 \| deadbeef$'
	[[ "$output" =~ $expected ]] || { echo "expected: the 24-octet message, then deadbeef after Decap"; return 1; }
}

@test "encap-push-pop: Encap then PushAVP then PopAVP keeps the frame consistent" {
	run_click encap-push-pop.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# 28 octets in (header plus one 8-octet AVP), 16 padded AVP octets appended
	# (Length 0x2c), then popped again (Length 0x1c). Only the identifiers
	# (F-11) vary.
	local expected='^encap: +28 \| 0100001c 80000118 00000000 [0-9a-f]{8} [0-9a-f]{8} 00000108 00000008
push: +44 \| 0100002c 80000118 00000000 [0-9a-f]{8} [0-9a-f]{8} 00000108 00000008 00000108 0000000d 61626364 65000000
pop: +28 \| 0100001c 80000118 00000000 [0-9a-f]{8} [0-9a-f]{8} 00000108 00000008$'
	[[ "$output" =~ $expected ]] || { echo "expected: 28, 44 and 28 octets with Lengths 0x1c, 0x2c and 0x1c"; return 1; }
}

@test "encap-error-on-answer: E is legal on an answer, flags 20" {
	run_click encap-error-on-answer.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	local expected='^encap-error-on-answer: +24 \| 01000018 20000118 00000000 [0-9a-f]{8} [0-9a-f]{8} deadbeef$'
	[[ "$output" =~ $expected ]] || { echo "expected: 24 octets, flags 20, code 000118, then the payload"; return 1; }
}

@test "encap-retransmit-on-request: T is legal on a request and unchecked, flags 90" {
	run_click encap-retransmit-on-request.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	local expected='^encap-retransmit-on-request: +24 \| 01000018 90000118 00000000 [0-9a-f]{8} [0-9a-f]{8} deadbeef$'
	[[ "$output" =~ $expected ]] || { echo "expected: 24 octets, flags 90, code 000118, then the payload"; return 1; }
}

@test "encap-proxiable-on-request: P is legal on a request, flags c0" {
	run_click encap-proxiable-on-request.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# The accept side of the P guard: a guard that rejected every PROXIABLE use,
	# or every request, fails here.
	local expected='^encap-proxiable-on-request: +24 \| 01000018 c0000118 00000000 [0-9a-f]{8} [0-9a-f]{8} deadbeef$'
	[[ "$output" =~ $expected ]] || { echo "expected: 24 octets, flags c0, code 000118, then the payload"; return 1; }
}

@test "encap-error-on-request: ERROR on a request fails to configure" {
	run_click encap-error-on-request.click
	expect_configure_failure encap-error-on-request.click 'the ERROR argument cannot be set on a request (RFC 6733 section 3)'
}

@test "encap-proxiable-on-answer: PROXIABLE on an answer fails to configure" {
	run_click encap-proxiable-on-answer.click
	expect_configure_failure encap-proxiable-on-answer.click 'the PROXIABLE argument cannot be set on an answer (RFC 6733 section 3)'
}

@test "rated-source: 20 octets, version 1, Length 20, flags 80, code 000118" {
	run_click rated-source.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	local expected='^rated-source: +20 \| 01000014 80000118 0000002a [0-9a-f]{8} [0-9a-f]{8}$'
	[[ "$output" =~ $expected ]] || { echo "expected: 20 octets, version 1, Length 20, flags 80, code 000118, App-Id 0000002a"; return 1; }
}

@test "rated-source-answer: 20 octets, flags 00, E and P clear on an answer" {
	run_click rated-source-answer.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	local expected='^rated-source-answer: +20 \| 01000014 00000118 0000002a [0-9a-f]{8} [0-9a-f]{8}$'
	[[ "$output" =~ $expected ]] || { echo "expected: 20 octets, version 1, Length 20, flags 00, code 000118, App-Id 0000002a"; return 1; }
}

@test "popstorepush-roundtrip: unpadded AVP pop then push restores the message" {
	run_click popstorepush-roundtrip.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	expect $'out0:   32 | 01000020 80000118 00000000 00000001 00000002 00000108 0000000a 61620000\nout1:   44 | 0100002c 80000118 00000000 00000001 00000002 00000108 0000000a 61620000 0000010c 0000000a 78790000'
}

@test "malformed-short-packet: 4-octet packet dropped by DiameterDecap" {
	run_click malformed-short-packet.click
	expect_drop DiameterDecap 'packet shorter than the 20-octet Diameter header'
}

@test "malformed-avpdecap-short: 6-octet packet dropped by DiameterAvpDecap" {
	run_click malformed-avpdecap-short.click
	expect_drop DiameterAvpDecap 'packet shorter than the 8-octet AVP header'
}

@test "malformed-avpdecap-v-short: 8-octet V AVP dropped by DiameterAvpDecap" {
	run_click malformed-avpdecap-v-short.click
	expect_drop DiameterAvpDecap 'packet shorter than the 12-octet vendor AVP header'
}

@test "malformed-zero-length-avp: DiameterPopAVP drops instead of hanging" {
	run_click malformed-zero-length-avp.click
	expect_drop DiameterPopAVP 'AVP length below its header'
}

@test "malformed-avp-short-length: AVP length 4 dropped by DiameterPopAVP" {
	run_click malformed-avp-short-length.click
	expect_drop DiameterPopAVP 'AVP length below its header'
}

@test "malformed-avp-past-message: AVP length 100 dropped by DiameterPopAVP" {
	run_click malformed-avp-past-message.click
	expect_drop DiameterPopAVP 'AVP extends past the message end'
}

@test "malformed-pushavp-length: header Length 100 dropped by DiameterPushAVP" {
	run_click malformed-pushavp-length.click
	expect_drop DiameterPushAVP 'header Length does not match packet length'
}

@test "malformed-popstorepush-avp-length: zero-length AVP dropped, nothing stored" {
	run_click malformed-popstorepush-avp-length.click
	expect_drop DiameterPopStorePushAVP 'AVP length below its header'
}

@test "malformed-length-short: header Length below the packet dropped by DiameterPushAVP" {
	run_click malformed-length-short.click
	expect_drop DiameterPushAVP 'header Length does not match packet length'
}

@test "malformed-avp-padding-overhang: padded AVP past the message dropped by DiameterPopAVP" {
	run_click malformed-avp-padding-overhang.click
	expect_drop DiameterPopAVP 'AVP extends past the message end'
}

@test "malformed-avp-trailing-octets: partial trailing AVP header dropped by DiameterPopAVP" {
	run_click malformed-avp-trailing-octets.click
	expect_drop DiameterPopAVP 'packet shorter than the 8-octet AVP header'
}

@test "malformed-decap-length: Length mismatch dropped by DiameterDecap" {
	run_click malformed-decap-length.click
	expect_drop DiameterDecap 'header Length does not match packet length'
}

@test "malformed-avpdecap-short-length: AVP length 4 dropped by DiameterAvpDecap" {
	run_click malformed-avpdecap-short-length.click
	expect_drop DiameterAvpDecap 'AVP length below its header'
}

@test "malformed-flip-request-short: 4-octet packet dropped by DiameterFlipRequest" {
	run_click malformed-flip-request-short.click
	expect_drop DiameterFlipRequest 'packet shorter than the 20-octet Diameter header'
}

@test "malformed-popstorepush-armed: malformed second pass dropped with an AVP armed" {
	run_click malformed-popstorepush-armed.click
	expect_drop DiameterPopStorePushAVP 'header Length does not match packet length'
}

@test "no-avp: header-only message forwarded unchanged by both pop elements" {
	run_click no-avp.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	expect $'pop-avp:   20 | 01000014 80000118 00000000 00000001 00000002\npop-store-push:   20 | 01000014 80000118 00000000 00000001 00000002'
}
