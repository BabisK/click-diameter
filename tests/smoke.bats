#!/usr/bin/env bats
#
# Byte-level assertions over the smoke configs in configs/.
#
#   bats --tap tests                              # click from PATH
#   CLICK=~/click/bin/click bats --tap tests      # explicit binary
#
# Requires bats-core. Every expectation below records what the element emits
# today: the point of the suite is that a change in the bytes fails the run.
# Where today's bytes are the known defect itself, the test names the finding
# so the story that fixes it updates the expectation in the same change. The
# malformed-* tests assert the drop path instead: exit 0, one warning naming
# the element and reason, and no Print line.

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

@test "push-avp: appending an AVP, header length updated" {
	run_click push-avp.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	expect 'push-avp:   32 | 01000020 80000118 00000000 00000001 00000002 00000108 0000000b 61626300'
}

@test "push-avp-rand: generated value, 8 characters" {
	run_click push-avp-rand.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	local generated='^push-avp-rand: +36 \| 01000024 80000118 00000000 00000001 00000002 00000108 00000010 [0-9a-f]{8} [0-9a-f]{8}$'
	[[ "$output" =~ $generated ]] || { echo "expected: 36 bytes, AVP length 16, 8 generated characters"; return 1; }
}

@test "pop-avp: removing the last AVP from a two-AVP message" {
	run_click pop-avp.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	expect 'pop-avp:   32 | 01000020 80000118 00000000 00000001 00000002 00000108 0000000a 61620000'
}

@test "avp-roundtrip: DiameterAvpEncap then DiameterAvpDecap returns the payload" {
	run_click avp-roundtrip.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# F-7: 13 bytes, unpadded to a 4-octet boundary; story 1-3 makes it 16
	# and leaves the decoded payload at 5 bytes.
	expect $'avp-encap:   13 | 00000108 0000000d 61626364 65\navp-decap:    5 | 61626364 65'
}

@test "flip-request: request bit cleared on a request" {
	run_click flip-request.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	expect 'flip-request:   20 | 01000014 00000118 00000000 00000001 00000002'
}

@test "decap: stripping the 20-byte header leaves the payload" {
	run_click decap.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	expect 'decap:    4 | deadbeef'
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
