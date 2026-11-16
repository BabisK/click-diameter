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
# so the story that fixes it updates the expectation in the same change.

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
