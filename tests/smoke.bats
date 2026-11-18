#!/usr/bin/env bats
#
# Byte-level assertions over the smoke configs in configs/.
#
#   bats --tap tests                              # click from PATH
#   CLICK=~/click/bin/click bats --tap tests      # explicit binary
#
# Requires bats-core 1.5 or newer (the seeded tests use BATS_TEST_TMPDIR) and a
# Click that carries the RandomSeed test element. Every expectation below pins
# the bytes the element emits today, so a change in them fails the run. A
# config that sets no RandomSeed varies its hbh/e2e identifiers per run, so the
# test matches them with a regex instead of pinning them, and the encap test
# runs its config a second time to check that every other field comes back byte
# for byte. The randomness-* configs pin RandomSeed(SEED 12345) and require the
# two packets of a run to differ, a rewritten seed to change the octets, and a
# rerun over a second later to reproduce the first run byte for byte, so a
# clock-seeded stream fails. The identifiers-* configs run 240 000 messages in
# Click's simulated time, and one 1 048 577-message run crosses the 2^20
# end-to-end carry; they require every hop-by-hop and end-to-end value to be
# distinct, consecutive, and never equal to the other field of the same frame
# (compared as strings), plus a byte-identical rerun where the run repeats, so a
# per-packet draw's birthday collisions and a counter that skips a value fail
# the run. randomness-encap-push-avp pins the stream position a seeded writer
# leaves for a downstream RAND* consumer. The rand-* tests pin the
# length and the alphabet of each DiameterPushAVP generator. The push-avp-vendor*
# configs pin the V=1 header bytes and the refusal of a zero Vendor-Id. The
# push-avp-uint32* configs pin A-3: a zero numeric value is a four-octet value at
# AVP Length 12 (16 with the vendor header), and a non-zero UINT32 is the same
# four octets;
# push-avp-empty, push-avp-empty-vendor and push-avp-no-value pin the no-value
# shapes that must stay at the header length. The push-avp tests compare
# whole frames -- literally, or as a pattern where a generated value cannot be
# pinned -- so the existing expectations that cover the AVP header, and so omit
# MANDATORY, pin M=0 as the regression half; push-avp-mandatory and
# push-avp-mandatory-vendor pin M=1 alone and composed with V, and
# push-avp-mandatory-false pins that an explicit false is M clear (the
# randomness-* and malformed-* configs never cover the AVP header). The
# avp-padding* and avp-decap-* tests pin the 4-octet AVP alignment of RFC 6733
# section 4.1 and the rule that the decoder derives padding from Length alone.
# The encap-unaligned-payload test pins the writer half of section 3's message
# rule: a payload that is not on a 4-octet boundary cannot be a sequence of padded
# AVPs, so DiameterEncap drops it rather than padding it into a plausible frame.
# encap-body-not-avps pins the limit of the remaining rule: a 4-octet body passes
# the writer because it is aligned, but an AVP reader still drops it, so
# alignment repairs the header's Length rule only. The
# malformed-* tests assert the drop path instead: exit 0, one warning naming the
# element and reason, and no Print line. They cover a bad Version, a short
# packet, an unaligned or mismatched Length, an over-long or malformed AVP, a V
# bit with a zero Vendor-Id, and an illegal flag. The not-aligned configs pin the
# reason precedence: the Version outranks the alignment, the short-header guard
# outranks it, and it outranks the Length mismatch.
# The twenty-one configs the package refuses -- ERROR on a request and
# RETRANSMITED on an answer in DiameterEncap, VENDORSPEC true without a non-zero
# VENDOR in DiameterPushAVP, two value sources in one DiameterPushAVP, a repeated
# keyword in each of the four configurable elements, a RAND*STRING count past the
# three-octet Length, and a CODE above the three-octet Command Code field in
# either writer -- assert the configure path: Click's whole configure-failure
# output and no Print line.
# push-avp-conflict-three pins that the error names the first conflicting pair
# in documented argument order rather than a later pair.
# push-avp-duplicate-wrapped pins that a repeat split across a line still fails:
# Click treats the newline as whitespace. push-avp-rand-zero and
# push-avp-randuint32-false pin the other side of the one-source rule: a zero
# generator count and a false RANDUINT32 are not sources, so each configures and
# prints a frame. The two code-max
# configs pin the inclusive Command Code ceiling: 16777215 (0xFFFFFF) is in
# range and prints ffffff, so an off-by-one guard fails there. The push-avp
# length pair pins the three-octet Message Length ceiling from both sides: an
# append one 4-octet step past it is dropped with its own warning, while the
# largest legal message still appends. `rated-source-timing` pins the unit the
# token bucket's refill timer is scheduled in: the two messages after the burst
# are 1 ms apart on either build, and a cast-only conversion reads FastClick's
# microseconds as jiffies and makes that a second. The smp-* tests are
# the ones run under `click -j 2`, with StaticThreadSched putting two producers
# on two router threads: the Encap and AvpEncap frames derive their Length from
# the packet, so a cross-thread write leaves the declared Length disagreeing
# with the printed octets, while the PushAVP frame is a shape check because its
# AVP Length comes from configuration, and the PopStorePushAVP frames are a
# shape and crash check because its shared store legitimately mixes the two
# producers' markers. The PopStorePushAVP loop pairs a pop on thread 0 with a
# push from a DelayUnqueue task on thread 1. All five skip on a Click built
# without multithread support, and none of them can see a race in shared value
# storage: ThreadSanitizer is what proves that.

click=${CLICK:-click}
# Simulated-time runs are CPU-bound, not wall-clock-bound: the RATE 10 pull
# config below spins through refused pulls for one simulated 0.3 s span, which
# measured 12.2 s at 3.19 GHz and 10.1 s on the CI runner, so the old 10 s bound
# killed a correct run. A hang still fails, only later; override with
# CLICK_TIMEOUT when a slower host needs more.
click_timeout=${CLICK_TIMEOUT:-30}

# run_config PATH -- run a config at PATH under a timeout, capturing the output.
run_config() {
	if command -v timeout >/dev/null 2>&1; then
		run timeout "$click_timeout" "$click" "$1"
	else
		run "$click" "$1"
	fi
}

# run_click CONFIG -- run configs/CONFIG under a timeout, capturing the output.
run_click() {
	run_config "$BATS_TEST_DIRNAME/configs/$1"
}

# run_click_simtime CONFIG OUTFILE -- run configs/CONFIG in Click's simulated
# time with stdout and stderr written straight to OUTFILE, so a million-line run
# never becomes a shell variable. Sets $status; the timeout still bounds the run.
run_click_simtime() {
	if command -v timeout >/dev/null 2>&1; then
		timeout "$click_timeout" "$click" --simtime "$BATS_TEST_DIRNAME/configs/$1" >"$2" 2>&1 && status=0 || status=$?
	else
		"$click" --simtime "$BATS_TEST_DIRNAME/configs/$1" >"$2" 2>&1 && status=0 || status=$?
	fi
}

# run_click_threads N CONFIG -- run configs/CONFIG on N router threads under a
# timeout, capturing the output. Needs a Click built with
# --enable-user-multithread; the caller skips instead of passing on one thread.
run_click_threads() {
	if command -v timeout >/dev/null 2>&1; then
		run timeout "$click_timeout" "$click" -j "$1" "$BATS_TEST_DIRNAME/configs/$2"
	else
		run "$click" -j "$1" "$BATS_TEST_DIRNAME/configs/$2"
	fi
}

# smp_skip_or_fail -- the gate every -j 2 test passes before reading frames.
# A Click built without --enable-user-multithread warns and then runs one
# thread, so there is no race to exercise and the test skips; check the run's
# status first so a config that failed for another reason cannot be skipped.
# A run that must carry two-thread coverage sets CLICK_REQUIRE_MULTITHREAD=1 --
# CI does -- and then a single-threaded build is a failure instead of a skip,
# because a green run without those five tests would claim coverage it never
# had. A Click that runs but rejects the config's thread preference has not put
# the producers on two threads either, and that is always a failure: it would
# silently turn the discriminating tests back into shape checks.
smp_skip_or_fail() {
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	if grep -qF 'Click was built without multithread support, running single threaded' <<<"$output"; then
		if [ "${CLICK_REQUIRE_MULTITHREAD:-0}" = 1 ]; then
			echo "CLICK_REQUIRE_MULTITHREAD=1 but this Click was built without multithread support"
			return 1
		fi
		skip "this Click was built without multithread support"
	fi
	if grep -qF 'thread preference' <<<"$output"; then
		echo "thread preference rejected, so the producers never reached two threads"
		return 1
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

# expect_configure_failure CONFIG ELEMENT MESSAGE -- a non-zero exit and Click's
# whole configure-failure output for that config: the config path and line, the
# element being configured, the named error, and the closing line. The element
# is a parameter because more than one element refuses a configuration. Click
# numbers the element in its suffix, so the @N part is matched with a wildcard.
# A crash, a second error, an extra warning or a packet that reached Print fails
# the run.
expect_configure_failure() {
	[ "$status" -ne 0 ] || { echo "expected a configure failure, click exit $status"; return 1; }
	local expected="$BATS_TEST_DIRNAME/configs/$1":*": While configuring '$2@* :: $2':"$'\n'"  $3"$'\n'"Router could not be initialized!"
	[[ "$output" == $expected ]] || { echo "expected: $expected"; echo "got: $output"; return 1; }
}

# expect_seeded CONFIG LENGTH [FIRST_FRAME] -- the RandomSeed(SEED 12345)
# contract for configs/CONFIG: rejection of a clock-seeded stream. Each of the
# two packets in the run must be LENGTH octets and the two must differ, because
# the stream advances rather than repeating one value. A copy with the seed
# rewritten must print different octets, so the seed rather than the clock or a
# constant decides. A rerun more than a second later must reproduce the first
# run byte for byte; two wall-clock-seeded runs in the same second agree, so the
# sleep is what makes a reseeded stream fail here instead of passing by
# accident. An optional third argument pins the first frame literally, so a
# change to the seed arithmetic or to the number of draws the writer consumes
# fails here; the bytes are Click's RNG output for SEED 12345, reproducible by
# design, not a libc-independent constant.
expect_seeded() {
	local config="$BATS_TEST_DIRNAME/configs/$1"
	run_config "$config"
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	local first_run="$output"
	local lines
	mapfile -t lines <<<"$first_run"
	[ "${#lines[@]}" -eq 2 ] || { echo "expected two packets, got ${#lines[@]}"; return 1; }
	local lengths
	lengths=$(awk '{ print $2 }' <<<"$first_run" | sort -u)
	[ "$lengths" = "$2" ] || { echo "expected $2-octet packets, got lengths: $lengths"; return 1; }
	[ "${lines[0]}" != "${lines[1]}" ] || { echo "expected the two packets to differ"; return 1; }
	if [ "$#" -ge 3 ]; then
		[ "${lines[0]}" = "$3" ] || { echo "expected the first frame to be: $3"; return 1; }
	fi

	local other="$BATS_TEST_TMPDIR/$1"
	sed -E 's/(RandomSeed\(SEED )[0-9]+\)/\154321)/' "$config" >"$other"
	if cmp -s "$config" "$other"; then
		echo "could not rewrite the seed in $1: no numeric RandomSeed(SEED n) found"
		return 1
	fi
	run_config "$other"
	[ "$status" -eq 0 ] || { echo "click exit $status with the rewritten seed"; return 1; }
	[ "$output" != "$first_run" ] || { echo "expected a different seed to print different octets"; return 1; }

	sleep 1.1
	run_config "$config"
	[ "$status" -eq 0 ] || { echo "click exit $status on the rerun"; return 1; }
	[ "$output" = "$first_run" ] || { echo "expected the rerun to reproduce the first run byte for byte"; return 1; }
}

# expect_identifier_run CONFIG COUNT [OUTFILE] -- one run of configs/CONFIG in
# Click's simulated time, asserting the identifier-counter contract: exactly
# COUNT printed frames, COUNT distinct hop-by-hop and end-to-end values, no frame
# whose two identifiers are equal as strings, and a consecutive sequence in each
# field. A per-packet draw repeats within COUNT values; a counter that skips a
# value (one stepped on a refused token, say) still has COUNT distinct values but
# fails the consecutive check; a clock-seeded start cannot reproduce a second
# run, which expect_unique_identifiers checks. Print puts hop-by-hop in field 7
# and end-to-end in field 8.
expect_identifier_run() {
	local count="$2"
	# No shell variable holds the frames: the wrap run prints 1 048 577 lines, and
	# copying that string into every awk call would dominate the test.
	local frames_file="${3:-$BATS_TEST_TMPDIR/identifier-frames}"
	run_click_simtime "$1" "$frames_file"
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# One pass computes the frame count, both distinct counts, the equal-pair
	# count and the first and last value of each field. Array subscripts are
	# strings, so the counts are string counts.
	local frames distinct_hbh distinct_e2e equal first_hbh last_hbh first_e2e last_e2e stats
	stats=$(awk '
		{
			frames++
			if (frames == 1) { f7 = $7; f8 = $8 }
			l7 = $7; l8 = $8
			seen7[$7] = 1
			seen8[$8] = 1
			if (($7 "") == ($8 "")) equal++
		}
		END {
			n7 = 0; for (k in seen7) n7++
			n8 = 0; for (k in seen8) n8++
			print frames, n7, n8, equal + 0, f7, l7, f8, l8
		}' "$frames_file")
	read -r frames distinct_hbh distinct_e2e equal first_hbh last_hbh first_e2e last_e2e <<<"$stats"
	[ "$frames" -eq "$count" ] || { echo "expected $count frames, got $frames"; return 1; }
	[ "$distinct_hbh" -eq "$count" ] || {
		echo "expected $count distinct hop-by-hop values, got $distinct_hbh"
		return 1
	}
	[ "$distinct_e2e" -eq "$count" ] || {
		echo "expected $count distinct end-to-end values, got $distinct_e2e"
		return 1
	}
	[ "$equal" -eq 0 ] || { echo "expected no frame with equal identifiers, got $equal"; return 1; }

	# COUNT distinct values in COUNT frames plus a span of COUNT - 1 proves the
	# sequence steps by exactly one: a value consumed elsewhere leaves a hole and
	# widens the span. 16# parses eight hex digits into 32 bits, and the mask
	# covers a wrap inside the run.
	local span
	span=$(( (16#$last_hbh - 16#$first_hbh) & 0xFFFFFFFF ))
	[ "$span" -eq "$((count - 1))" ] || {
		echo "hop-by-hop values are not consecutive: $first_hbh to $last_hbh over $count frames"
		return 1
	}
	span=$(( (16#$last_e2e - 16#$first_e2e) & 0xFFFFFFFF ))
	[ "$span" -eq "$((count - 1))" ] || {
		echo "end-to-end values are not consecutive: $first_e2e to $last_e2e over $count frames"
		return 1
	}
}

# expect_unique_identifiers CONFIG COUNT -- the single-run contract above plus a
# byte-identical second run, so a clock-seeded start fails.
expect_unique_identifiers() {
	local first="$BATS_TEST_TMPDIR/identifier-frames-first"
	local second="$BATS_TEST_TMPDIR/identifier-frames-second"
	expect_identifier_run "$1" "$2" "$first" || return 1
	run_click_simtime "$1" "$second"
	[ "$status" -eq 0 ] || { echo "click exit $status on the rerun"; return 1; }
	cmp -s "$first" "$second" || { echo "expected the rerun to reproduce the first run byte for byte"; return 1; }
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

@test "push-avp-vendor: a vendor AVP carries its Vendor-Id and the V flag" {
	run_click push-avp-vendor.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# 20-octet request plus a 12-octet header, a 3-octet value and one zero pad
	# octet: 36 octets, Length 0x24, AVP flags 80, AVP Length 0x0f, Vendor-Id 42.
	expect 'push-avp-vendor:   36 | 01000024 80000118 00000000 00000001 00000002 00000108 8000000f 0000002a 61626300'
}

@test "push-avp-vendor-missing: VENDORSPEC without VENDOR fails to configure" {
	run_click push-avp-vendor-missing.click
	# A-1: RFC 6733 section 4.1.1 forbids Vendor-Id zero with V set, so the
	# absent VENDOR is refused instead of writing an indeterminate id.
	expect_configure_failure push-avp-vendor-missing.click DiameterPushAVP 'the VENDOR argument must be non-zero when VENDORSPEC is true (RFC 6733 section 4.1.1)'
}

@test "push-avp-vendor-zero: VENDOR 0 with VENDORSPEC fails to configure" {
	run_click push-avp-vendor-zero.click
	# An explicit zero is the same forbidden value as the absent argument.
	expect_configure_failure push-avp-vendor-zero.click DiameterPushAVP 'the VENDOR argument must be non-zero when VENDORSPEC is true (RFC 6733 section 4.1.1)'
}

@test "push-avp-conflict-octetstring-uint32: two value sources fail to configure" {
	run_click push-avp-conflict-octetstring-uint32.click
	# A-10: OCTETSTRING and UINT32 used to resolve by if/else order, so the
	# string was emitted and the number -- the argument that decides the value
	# type -- was discarded. At most one source is allowed.
	expect_configure_failure push-avp-conflict-octetstring-uint32.click DiameterPushAVP 'the OCTETSTRING and UINT32 arguments cannot be used together: at most one value source may be supplied'
}

@test "push-avp-conflict-randnumstring-randhexstring: two generators fail to configure" {
	run_click push-avp-conflict-randnumstring-randhexstring.click
	# The same rule on the generator pair that used to take the first silently.
	expect_configure_failure push-avp-conflict-randnumstring-randhexstring.click DiameterPushAVP 'the RANDNUMSTRING and RANDHEXSTRING arguments cannot be used together: at most one value source may be supplied'
}

@test "push-avp-conflict-empty-octetstring-uint32: an empty string is still a source" {
	run_click push-avp-conflict-empty-octetstring-uint32.click
	# The empty string requests the no-value AVP and the zero is a value, so both
	# keywords are supplied even though both parsed values look empty. A presence
	# test based on the value's length or magnitude would configure here.
	expect_configure_failure push-avp-conflict-empty-octetstring-uint32.click DiameterPushAVP 'the OCTETSTRING and UINT32 arguments cannot be used together: at most one value source may be supplied'
}

@test "push-avp-conflict-octetstring-randuint32: a true boolean is a second source" {
	run_click push-avp-conflict-octetstring-randuint32.click
	# RANDUINT32 is a source only when true, so a presence table that dropped
	# this row would let the configuration through and the draw would win.
	expect_configure_failure push-avp-conflict-octetstring-randuint32.click DiameterPushAVP 'the OCTETSTRING and RANDUINT32 arguments cannot be used together: at most one value source may be supplied'
}

@test "push-avp-conflict-randalphanumstring-randalphastring: two string generators fail to configure" {
	run_click push-avp-conflict-randalphanumstring-randalphastring.click
	# Both generator rows supply one character each, so neither may be dropped
	# from the presence table.
	expect_configure_failure push-avp-conflict-randalphanumstring-randalphastring.click DiameterPushAVP 'the RANDALPHANUMSTRING and RANDALPHASTRING arguments cannot be used together: at most one value source may be supplied'
}

@test "push-avp-conflict-three: three value sources name the first pair in order" {
	run_click push-avp-conflict-three.click
	# The error names the first conflicting pair in documented argument order,
	# OCTETSTRING before UINT32, rather than the last source encountered.
	expect_configure_failure push-avp-conflict-three.click DiameterPushAVP 'the OCTETSTRING and UINT32 arguments cannot be used together: at most one value source may be supplied'
}

@test "push-avp-vendor-unused: VENDOR without VENDORSPEC leaves the AVP non-vendor" {
	run_click push-avp-vendor-unused.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# The Vendor-Id is ignored without VENDORSPEC: the frame is the same 32
	# octets as push-avp.click, with an 8-octet header and no V bit.
	expect 'push-avp-vendor-unused:   32 | 01000020 80000118 00000000 00000001 00000002 00000108 0000000b 61626300'
}

@test "push-avp-mandatory: MANDATORY true sets the M bit, flags 40" {
	run_click push-avp-mandatory.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# A-2: the same 32 octets as push-avp.click except that the AVP flags are
	# 40 rather than 00. M is the only octet the argument may move.
	expect 'push-avp-mandatory:   32 | 01000020 80000118 00000000 00000001 00000002 00000108 4000000b 61626300'
}

@test "push-avp-mandatory-vendor: M and V occupy separate bits, flags c0" {
	run_click push-avp-mandatory-vendor.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# M is 0x40 and V is 0x80, so a mandatory vendor AVP carries c0 in its
	# flags octet: 36 octets, AVP Length 0x0f, Vendor-Id 42.
	expect 'push-avp-mandatory-vendor:   36 | 01000024 80000118 00000000 00000001 00000002 00000108 c000000f 0000002a 61626300'
}

@test "push-avp-mandatory-false: an explicit false keeps the M bit clear" {
	run_click push-avp-mandatory-false.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# The argument's false value is M clear, not "argument present means set":
	# the frame is byte-identical to push-avp.click.
	expect 'push-avp-mandatory-false:   32 | 01000020 80000118 00000000 00000001 00000002 00000108 0000000b 61626300'
}

@test "push-avp-uint32-zero: UINT32 0 is four zero octets, AVP Length 12" {
	run_click push-avp-uint32-zero.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# A-3: RFC 6733 section 4.2 fixes Unsigned32 at AVP Length 12, so the
	# frame is 32 octets with a four-octet zero value, not a header-only AVP.
	expect 'push-avp-uint32-zero:   32 | 01000020 80000118 00000000 00000001 00000002 0000010c 0000000c 00000000'
}

@test "push-avp-uint32-zero-vendor: UINT32 0 after the vendor header is Length 16" {
	run_click push-avp-uint32-zero-vendor.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# The same four zero octets after a 12-octet header: AVP Length 16, so the
	# frame is 36 octets, per the "16 if the V bit is enabled" half of 4.2.
	expect 'push-avp-uint32-zero-vendor:   36 | 01000024 80000118 00000000 00000001 00000002 0000010c 80000010 0000002a 00000000'
}

@test "push-avp-empty: no value source keeps the header-only AVP" {
	run_click push-avp-empty.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# The permitted empty-value case: an empty OCTETSTRING is an 8-octet AVP
	# with Length 8, the same bytes as the pre-change build. A fix that emits
	# four octets for every AVP fails here.
	expect 'push-avp-empty:   28 | 0100001c 80000118 00000000 00000001 00000002 00000108 00000008'
}

@test "push-avp-empty-vendor: the no-value case after the vendor header is Length 12" {
	run_click push-avp-empty-vendor.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# The same no-value AVP with the 12-octet vendor header: Length 12 carries
	# no value, so the frame is 32 octets. "At least 8" is an OctetString rule,
	# so this shape is only conformant for an OctetString AVP.
	expect 'push-avp-empty-vendor:   32 | 01000020 80000118 00000000 00000001 00000002 00000108 8000000c 0000002a'
}

@test "push-avp-no-value: no string and no numeric source is a header-only AVP" {
	run_click push-avp-no-value.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# The other input the no-value rule covers: neither OCTETSTRING nor a
	# numeric source is supplied, so the AVP is its 8-octet header alone.
	expect 'push-avp-no-value:   28 | 0100001c 80000118 00000000 00000001 00000002 00000108 00000008'
}

@test "push-avp-uint32: a non-zero UINT32 is the four-octet big-endian value" {
	run_click push-avp-uint32.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# The numeric path the presence rule keys off: UINT32 2001 is 000007d1, so
	# the AVP Length is 12 and the frame 32 octets.
	expect 'push-avp-uint32:   32 | 01000020 80000118 00000000 00000001 00000002 0000010c 0000000c 000007d1'
}

@test "push-avp-randuint32-false: a false boolean is not a value source" {
	run_click push-avp-randuint32-false.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# RANDUINT32 false is its default, so it supplies nothing and OCTETSTRING is
	# the single source: the frame is byte-identical to push-avp.click. Counting
	# a present-but-false boolean as a source would refuse this configuration.
	expect 'push-avp-randuint32-false:   32 | 01000020 80000118 00000000 00000001 00000002 00000108 0000000b 61626300'
}

@test "push-avp-randuint32-zero: a zero draw is a four-octet value, AVP Length 12" {
	run_click push-avp-randuint32-zero.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# SEED 808357014 makes Click's first random() draw zero, so the drawn value is
	# four zero octets rather than an empty AVP: AVP Length 12, frame 32 octets.
	expect 'push-avp-randuint32-zero:   32 | 01000020 80000118 00000000 00000001 00000002 0000010c 0000000c 00000000'
}

@test "push-avp-rand-zero: a zero generator count is unused, not a second source" {
	run_click push-avp-rand-zero.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# RANDNUMSTRING 0 is the documented "unused" value, so RANDHEXSTRING 4 is
	# the single source: AVP Length 12 and four hex characters after the header.
	local expected='^push-avp-rand-zero: +32 \| 01000020 80000118 00000000 00000001 00000002 00000108 0000000c (3[0-9]|4[1-6]){4}$'
	[[ "$output" =~ $expected ]] || { echo "expected: 32 octets, AVP Length 12, four hex characters"; return 1; }
}

@test "push-avp-duplicate-octetstring: a repeated keyword fails configuration" {
	run_click push-avp-duplicate-octetstring.click
	# A repeated keyword used to be Click's last-wins, silently discarding the
	# first value; it is now a caller error naming the repeated argument.
	expect_configure_failure push-avp-duplicate-octetstring.click DiameterPushAVP 'the OCTETSTRING argument is given more than once'
}

@test "push-avp-duplicate-wrapped: a repeat split across a line still fails" {
	run_click push-avp-duplicate-wrapped.click
	# Click treats the newline as whitespace, so `MANDATORY true, MANDATORY
	# <newline>false` is two arguments; the scan must end a keyword at any
	# whitespace or this configuration silently keeps the last value.
	expect_configure_failure push-avp-duplicate-wrapped.click DiameterPushAVP 'the MANDATORY argument is given more than once'
}

@test "encap-duplicate-code: a repeated keyword fails configuration" {
	run_click encap-duplicate-code.click
	# The same guard runs in every configurable element of the package.
	expect_configure_failure encap-duplicate-code.click DiameterEncap 'the CODE argument is given more than once'
}

@test "rated-source-duplicate-rate: a repeated keyword fails configuration" {
	run_click rated-source-duplicate-rate.click
	# RATE is also a positional argument; a repeat after the first keyword is
	# caught by the same guard.
	expect_configure_failure rated-source-duplicate-rate.click DiameterRatedSource 'the RATE argument is given more than once'
}

@test "push-avp-randhex-too-large: a generator count past 16,777,184 fails configuration" {
	run_click push-avp-randhex-too-large.click
	# The value plus the AVP and message headers cannot fit the three-octet
	# Length, so it is refused before it is materialised per packet.
	expect_configure_failure push-avp-randhex-too-large.click DiameterPushAVP 'the RANDHEXSTRING argument must not exceed 16777184: a larger value cannot fit the three-octet message Length (RFC 6733 section 3)'
}

@test "push-avp-randhex-too-large-vendor: the vendor header lowers the limit to 16,777,180" {
	run_click push-avp-randhex-too-large-vendor.click
	# The 12-octet vendor header leaves four fewer octets than the 8-octet one.
	expect_configure_failure push-avp-randhex-too-large-vendor.click DiameterPushAVP 'the RANDHEXSTRING argument must not exceed 16777180: a larger value cannot fit the three-octet message Length (RFC 6733 section 3)'
}

@test "push-avp-length-overflow: an append past 0xFFFFFF is dropped, not wrapped" {
	run_click push-avp-length-overflow.click
	# A-9: the first PushAVP fills the message to the largest legal 16,777,212
	# octets, and the second appends an 8-octet AVP, which would reach 16,777,220.
	# The guard runs before put(), so the drop is one line; the 16 MB append of
	# the first AVP makes Click print its Put advisory beside it.
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	local others
	others=$(grep -v '^expensive Packet::put' <<<"$output" || true)
	[ "$others" = 'DiameterPushAVP: dropping packet: appending the AVP would exceed the three-octet Length field (RFC 6733 section 3)' ] || { echo "unexpected output: $others"; return 1; }
}

@test "push-avp-length-max: the largest legal message still appends" {
	run_click push-avp-length-max.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# One 4-octet step below the overflow config: 16,777,212 octets (0xFFFFFC)
	# is the largest multiple of 4 at or below the ceiling, so the AVP is
	# appended and the header carries Length 0xfffffc. Print shows the first 36
	# octets -- the message header, the appended AVP header (Code 0x00000108,
	# Length 0xFFFFE8) and the first 8 value octets, 16 hex digits in two
	# 8-digit groups -- and the 16 MB append makes Click print one advisory.
	local printed others
	printed=$(grep '^push-avp-length-max:' <<<"$output")
	others=$(grep -v '^push-avp-length-max:' <<<"$output" | grep -v '^expensive Packet::put' || true)
	[ -z "$others" ] || { echo "unexpected output beside the Print line: $others"; return 1; }
	local header='^push-avp-length-max: +16777212 \| 01fffffc 80000118 00000000 00000001 00000002 00000108 00ffffe8 (3[0-9]|4[1-6]){4} (3[0-9]|4[1-6]){4}$'
	[[ "$printed" =~ $header ]] || { echo "expected: 16,777,212 octets, Length 0xfffffc, AVP Length 0xffffe8 and 16 generated hex digits"; return 1; }
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

@test "smp-push-avp: two sources into one PushAVP stay per packet under -j 2" {
	run_click_threads 2 smp-push-avp.click
	smp_skip_or_fail
	# Two header-only 20-octet requests into one append: every frame is the
	# 20-octet message header, the 8-octet AVP header and the 8-octet generated
	# value, 36 octets, message Length 0x24 and AVP Length 0x10. This is a
	# shape check, not a race detector: the appended Length comes from
	# configuration, so no interleaving can change it. The sources carry
	# different Command Codes, and the floor above one LIMIT proves both pushed.
	# The value is hex output, so pin the generator's alphabet per four octets:
	# a byte from "0"-"9" prints as 3x and one from "A"-"F" as 4x.
	local frame='^smp-push-avp: +36 \| 01000024 (80000118|80000119) 00000000 [0-9a-f]{8} [0-9a-f]{8} 00000108 00000010 (3[0-9]|4[1-6]){4} (3[0-9]|4[1-6]){4}$'
	local count=0 line
	while IFS= read -r line; do
		[[ "$line" =~ $frame ]] || { echo "unexpected frame: $line"; return 1; }
		count=$((count + 1))
	done <<<"$output"
	[ "$count" -gt 1000 ] || { echo "expected more than one source's 1000 frames, got $count"; return 1; }
	grep -q '80000118' <<<"$output" || { echo "expected frames from the CODE 280 source"; return 1; }
	grep -q '80000119' <<<"$output" || { echo "expected frames from the CODE 281 source"; return 1; }
}

@test "smp-encap: two payload lengths through one Encap stay per packet under -j 2" {
	run_click_threads 2 smp-encap.click
	smp_skip_or_fail
	# Encap derives the message Length from the packet in hand, so a
	# cross-thread write between setLength and encode prints a frame whose
	# Length field contradicts its octet count. Each frame must be one of the
	# two shapes the payloads produce -- 4 octets give 24 with Length 0x18 and
	# 8 octets give 28 with 0x1c -- so a frame that matches neither is the
	# cross-thread write. Both shapes must appear and the count must exceed one
	# source's LIMIT, so a run where only one producer got through fails.
	local four='^smp-encap: +24 \| 01000018 80000118 00000000 [0-9a-f]{8} [0-9a-f]{8} deadbeef$'
	local eight='^smp-encap: +28 \| 0100001c 80000118 00000000 [0-9a-f]{8} [0-9a-f]{8} deadbeef 01020304$'
	local count=0 fours=0 eights=0 line
	while IFS= read -r line; do
		if [[ "$line" =~ $four ]]; then
			fours=$((fours + 1))
		elif [[ "$line" =~ $eight ]]; then
			eights=$((eights + 1))
		else
			echo "unexpected frame: $line"
			return 1
		fi
		count=$((count + 1))
	done <<<"$output"
	[ "$count" -gt 5000 ] || { echo "expected more than one source's 5000 frames, got $count"; return 1; }
	[ "$fours" -gt 0 ] || { echo "expected 24-octet frames from the 4-octet payload"; return 1; }
	[ "$eights" -gt 0 ] || { echo "expected 28-octet frames from the 8-octet payload"; return 1; }
}

@test "smp-avpencap: two payload lengths through one AvpEncap stay per packet under -j 2" {
	run_click_threads 2 smp-avpencap.click
	smp_skip_or_fail
	# AvpEncap derives the AVP Length from the packet in hand, so the same
	# cross-thread write leaves an AVP Length that disagrees with the octets
	# printed after it. A 4-octet value is a 12-octet AVP with Length 0x0c and
	# an 8-octet value a 16-octet AVP with Length 0x10; neither needs padding.
	# A frame that matches neither shape is the cross-thread write.
	local four='^smp-avpencap: +12 \| 00000108 0000000c deadbeef$'
	local eight='^smp-avpencap: +16 \| 00000108 00000010 deadbeef 01020304$'
	local count=0 fours=0 eights=0 line
	while IFS= read -r line; do
		if [[ "$line" =~ $four ]]; then
			fours=$((fours + 1))
		elif [[ "$line" =~ $eight ]]; then
			eights=$((eights + 1))
		else
			echo "unexpected frame: $line"
			return 1
		fi
		count=$((count + 1))
	done <<<"$output"
	[ "$count" -gt 5000 ] || { echo "expected more than one source's 5000 frames, got $count"; return 1; }
	[ "$fours" -gt 0 ] || { echo "expected 12-octet frames from the 4-octet value"; return 1; }
	[ "$eights" -gt 0 ] || { echo "expected 16-octet frames from the 8-octet value"; return 1; }
}

@test "smp-popstorepush: one store pairs packets across two threads under -j 2" {
	run_click_threads 2 smp-popstorepush.click
	smp_skip_or_fail
	# One element, one store, two threads: every input yields exactly one output
	# frame, so every line must be the 32-octet remainder of an unarmed packet
	# (message Length 0x20, the first 12-octet AVP) or the 56-octet message of
	# an armed one (Length 0x38, its own two AVPs and the stored one). The AVP
	# Length 0x0c is pinned against the four octets that follow it, so a header
	# decoded by one thread and encoded by another fails here, and a crash fails
	# the exit-status gate above. The store is shared, so an output-1 frame may
	# mix the two markers and a legal perfect alternation can put one producer
	# only on the armed slot; the test therefore requires both producers'
	# hop-by-hop and end-to-end pairs somewhere in the output and both outputs to
	# be non-empty, not each marker on each output. The frame floor proves the
	# second producer ran too.
	local zero='^smp-popstorepush-out0: +32 \| 01000020 80000118 00000000 (00000001 00000002|00000003 00000004) 00000109 4000000c (41414141|42424242)$'
	local one='^smp-popstorepush-out1: +56 \| 01000038 80000118 00000000 (00000001 00000002|00000003 00000004) 00000109 4000000c (41414141|42424242) 00000108 4000000c (41414141|42424242) 00000108 4000000c (41414141|42424242)$'
	local count=0 line
	while IFS= read -r line; do
		[[ "$line" =~ $zero || "$line" =~ $one ]] || { echo "unexpected frame: $line"; return 1; }
		count=$((count + 1))
	done <<<"$output"
	[ "$count" -gt 5000 ] || { echo "expected more than one source's 5000 frames, got $count"; return 1; }
	local out0 out1 producer
	out0=$(grep '^smp-popstorepush-out0:' <<<"$output")
	out1=$(grep '^smp-popstorepush-out1:' <<<"$output")
	[ -n "$out0" ] || { echo "expected frames on output 0"; return 1; }
	[ -n "$out1" ] || { echo "expected frames on output 1"; return 1; }
	for producer in '00000001 00000002' '00000003 00000004'; do
		grep -qF "$producer" <<<"$output" || { echo "expected producer $producer in the output"; return 1; }
	done
}

@test "smp-popstorepush-loop: an AVP stored on one thread is appended on another" {
	run_click_threads 2 smp-popstorepush-loop.click
	smp_skip_or_fail
	# The pop runs on thread 0. Its 32-octet remainder crosses a Queue, so the
	# DelayUnqueue task bound to thread 1 pushes it back into the element, where
	# the shared store must still hold the AVP popped on thread 0. A per-thread
	# store would find nothing on thread 1: it would pop the remainder's only
	# AVP, print a second 20-octet output-0 frame and never the 44-octet
	# output-1 frame. Pin both frames exactly; the stop timer only ends the run.
	expect $'out0:   32 | 01000020 80000118 00000000 00000001 00000002 00000108 0000000a 61620000\nout1:   44 | 0100002c 80000118 00000000 00000001 00000002 00000108 0000000a 61620000 0000010c 0000000a 78790000'
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

@test "avp-encap-length-overflow: an AVP past 0xFFFFFF is dropped, not wrapped" {
	run_click avp-encap-length-overflow.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# The value alone would make the three-octet AVP Length wrap, so the
	# envelope is dropped with its own warning and nothing reaches Print.
	expect 'DiameterAvpEncap: dropping packet: the AVP Length would exceed the three-octet field (RFC 6733 section 4.1)'
}

@test "avp-encap-length-max: the largest legal AVP Length still emits" {
	run_click avp-encap-length-max.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# One octet below the overflow config: 16,777,207 value octets plus the
	# 8-octet header is 0xFFFFFF, so the guard must be > rather than >=. The
	# 16 MB append makes Click print one Put advisory beside the Print line.
	local printed others
	printed=$(grep '^avp-encap-length-max:' <<<"$output")
	others=$(grep -v '^avp-encap-length-max:' <<<"$output" | grep -v '^expensive Packet::put' || true)
	[ -z "$others" ] || { echo "unexpected output beside the Print line: $others"; return 1; }
	[ "$printed" = 'avp-encap-length-max: 16777216 | 00000108 00ffffff' ] || { echo "unexpected line: $printed"; return 1; }
}

@test "avp-encap-length-max-vendor: the vendor header's inclusive ceiling emits" {
	run_click avp-encap-length-max-vendor.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# 16,777,203 value octets plus the 12-octet vendor header is 0xFFFFFF; the
	# AVP carries flags 80, Length ffffff and Vendor-Id 42. The 16 MB append
	# makes Click print one Put advisory beside the Print line.
	local printed others
	printed=$(grep '^avp-encap-length-max-vendor:' <<<"$output")
	others=$(grep -v '^avp-encap-length-max-vendor:' <<<"$output" | grep -v '^expensive Packet::put' || true)
	[ -z "$others" ] || { echo "unexpected output beside the Print line: $others"; return 1; }
	[ "$printed" = 'avp-encap-length-max-vendor: 16777216 | 00000108 80ffffff 0000002a' ] || { echo "unexpected line: $printed"; return 1; }
}

@test "avp-encap-duplicate-code: a repeated keyword fails configuration" {
	run_click avp-encap-duplicate-code.click
	# The shared duplicate guard runs in all four configurable elements; this is
	# the fourth one's own path.
	expect_configure_failure avp-encap-duplicate-code.click DiameterAvpEncap 'the CODE argument is given more than once'
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
	# AVP and restores a header-only 20-octet message. The config sets no seed,
	# so the identifiers vary per run and the test regexes them.
	local expected='^message: +36 \| 01000024 80000118 00000000 [0-9a-f]{8} [0-9a-f]{8} 00000108 0000000d 61626364 65000000
pop: +20 \| 01000014 80000118 00000000 [0-9a-f]{8} [0-9a-f]{8}$'
	[[ "$output" =~ $expected ]] || { echo "expected: the 36-octet message, then the 20-octet header-only frame"; return 1; }
}

@test "flip-request: request bit cleared on a request" {
	run_click flip-request.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	expect 'flip-request:   20 | 01000014 00000118 00000000 00000001 00000002'
}

@test "flip-request-p: a proxiable request flips to flags 40, P mirrored" {
	run_click flip-request-p.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# RFC 6733 section 6.2: an answer's P is the request's P, so R clears and P
	# stays. A flip that clears P again fails here.
	expect 'flip-request-p:   20 | 01000014 40000118 00000000 00000001 00000002'
}

@test "flip-request-t: a retransmitted request flips to flags 00, T cleared with R" {
	run_click flip-request-t.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	expect 'flip-request-t:   20 | 01000014 00000118 00000000 00000001 00000002'
}

@test "flip-request-pt: P is mirrored and T cleared, flags d0 to 40" {
	run_click flip-request-pt.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	expect 'flip-request-pt:   20 | 01000014 40000118 00000000 00000001 00000002'
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

@test "flip-answer-e: a flipped error answer clears E, flags 20 to 80" {
	run_click flip-answer-e.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	expect 'flip-answer-e:   20 | 01000014 80000118 00000000 00000001 00000002'
}

@test "flip-answer-ep: a flipped proxiable error answer keeps P and clears E, flags 60 to c0" {
	run_click flip-answer-ep.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	expect 'flip-answer-ep:   20 | 01000014 c0000118 00000000 00000001 00000002'
}

@test "decap: stripping the 20-byte header leaves the AVP body" {
	run_click decap.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	expect 'decap:    8 | 00000108 00000008'
}

@test "decap-p-on-answer: P on an answer is not an error, body forwarded" {
	run_click decap-p-on-answer.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# The receive rule polices E and T only; P is legal on either type, so a
	# guard that dropped P would fail here.
	expect 'decap-p-on-answer:    8 | 00000108 00000008'
}

@test "decap-t-on-request: T on a request is not an error, body forwarded" {
	run_click decap-t-on-request.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	expect 'decap-t-on-request:    8 | 00000108 00000008'
}

@test "pop-avp-error-on-answer: E on an answer is forwarded unchanged" {
	run_click pop-avp-error-on-answer.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	expect 'pop-avp-e:   20 | 01000014 20000118 00000000 00000001 00000002'
}

@test "encap: version 1, Length counts the header plus the payload" {
	run_click encap.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# F-4: version, Length, flags, code and App-Id are asserted exactly; only the
	# unseeded hbh/e2e are regexed.
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

@test "encap-unaligned-payload: a payload that cannot be padded AVPs is dropped" {
	run_click encap-unaligned-payload.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# CAP-2/A-4: the writer used to zero-pad the tail of a 5-octet payload into
	# a plausible 28-octet frame. That body is not an AVP sequence, so the
	# frame was one its own readers reject; it is now dropped with its own line
	# and nothing reaches Print.
	expect 'DiameterEncap: dropping packet: the payload length is not a multiple of 4, so it cannot be a sequence of padded AVPs (RFC 6733 section 3)'
}

@test "encap-body-not-avps: alignment does not make an arbitrary body walkable" {
	run_click encap-body-not-avps.click
	# A 4-octet body passes the writer (it is aligned), but it is not an AVP
	# sequence, so DiameterPushAVP drops it. Alignment repairs the header's
	# Length rule only; the body is the caller's.
	expect_drop DiameterPushAVP 'packet shorter than the 8-octet AVP header'
}

@test "encap-length-overflow: a message past 0xFFFFFF is dropped, not wrapped" {
	run_click encap-length-overflow.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# A 16,777,200-octet payload plus the 20-octet header exceeds the three-octet
	# Message Length; the frame is dropped before push().
	expect 'DiameterEncap: dropping packet: the message Length would exceed the three-octet field (RFC 6733 section 3)'
}

@test "encap-decap: the encapsulated AVP body survives Decap without a drop" {
	run_click encap-decap.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# Only the two Print lines: any drop warning fails the regex. The body is a
	# valid AVP because Decap validates the whole message.
	local expected='^encap: +28 \| 0100001c 80000118 00000000 [0-9a-f]{8} [0-9a-f]{8} 00000108 00000008
decap: +8 \| 00000108 00000008$'
	[[ "$output" =~ $expected ]] || { echo "expected: the 28-octet message, then the AVP after Decap"; return 1; }
}

@test "encap-push-pop: Encap then PushAVP then PopAVP keeps the frame consistent" {
	run_click encap-push-pop.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# 28 octets in (header plus one 8-octet AVP), 16 padded AVP octets appended
	# (Length 0x2c), then popped again (Length 0x1c). Only the unseeded
	# identifiers vary.
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
	# P is legal on either type now, so a guard that rejected PROXIABLE at all
	# fails here.
	local expected='^encap-proxiable-on-request: +24 \| 01000018 c0000118 00000000 [0-9a-f]{8} [0-9a-f]{8} deadbeef$'
	[[ "$output" =~ $expected ]] || { echo "expected: 24 octets, flags c0, code 000118, then the payload"; return 1; }
}

@test "encap-error-on-request: ERROR on a request fails to configure" {
	run_click encap-error-on-request.click
	expect_configure_failure encap-error-on-request.click DiameterEncap 'the ERROR argument cannot be set on a request (RFC 6733 section 3)'
}

@test "encap-code-too-large: CODE above 0xFFFFFF fails to configure" {
	run_click encap-code-too-large.click
	# A-9: the Command Code is three octets (RFC 6733 section 3), so 0x01000118
	# cannot be encoded and used to be truncated to 0x000118 without a warning.
	expect_configure_failure encap-code-too-large.click DiameterEncap 'the CODE argument must not exceed 0xFFFFFF: the Command Code field is three octets (RFC 6733 section 3)'
}

@test "encap-code-first-too-large: the first illegal CODE fails to configure" {
	run_click encap-code-first-too-large.click
	# 16777216 is 0x1000000, the smallest value that does not fit three octets.
	# A guard that is lenient by up to the 0x01000118 repro value passes every
	# test without this one.
	expect_configure_failure encap-code-first-too-large.click DiameterEncap 'the CODE argument must not exceed 0xFFFFFF: the Command Code field is three octets (RFC 6733 section 3)'
}

@test "encap-code-max: CODE 0xFFFFFF is in range and prints ffffff" {
	run_click encap-code-max.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# The ceiling is inclusive, and RFC 6733 section 3.1 reserves 0xFFFFFF for
	# experimental use rather than forbidding it. A guard written as >= rejects
	# this config instead of printing the 24-octet frame.
	local expected='^encap-code-max: +24 \| 01000018 80ffffff 00000000 [0-9a-f]{8} [0-9a-f]{8} deadbeef$'
	[[ "$output" =~ $expected ]] || { echo "expected: 24 octets, code ffffff, then the payload"; return 1; }
}

@test "encap-proxiable-on-answer: P is legal on either type, flags 40" {
	run_click encap-proxiable-on-answer.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# RFC 6733 section 6.2 mirrors a request's P into the answer; Encap has no
	# request to consult, so the caller's declaration stands. A guard that
	# rejects PROXIABLE on an answer again fails here.
	local expected='^encap-proxiable-on-answer: +24 \| 01000018 40000118 00000000 [0-9a-f]{8} [0-9a-f]{8} deadbeef$'
	[[ "$output" =~ $expected ]] || { echo "expected: 24 octets, flags 40, code 000118, then the payload"; return 1; }
}

@test "encap-retransmit-on-answer: RETRANSMITED on an answer fails to configure" {
	run_click encap-retransmit-on-answer.click
	expect_configure_failure encap-retransmit-on-answer.click DiameterEncap 'the RETRANSMITED argument cannot be set on an answer (RFC 6733 section 3)'
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

@test "rated-source-code-too-large: CODE above 0xFFFFFF fails to configure" {
	run_click rated-source-code-too-large.click
	# A-9's second writer: DiameterRatedSource shares DiameterHeader::setCode(),
	# so it must refuse the same value with the same error.
	expect_configure_failure rated-source-code-too-large.click DiameterRatedSource 'the CODE argument must not exceed 0xFFFFFF: the Command Code field is three octets (RFC 6733 section 3)'
}

@test "rated-source-code-first-too-large: the first illegal CODE fails to configure" {
	run_click rated-source-code-first-too-large.click
	# 0x1000000 must fail in the second writer too, so a lenient guard cannot
	# hide behind the larger repro value in either configure path.
	expect_configure_failure rated-source-code-first-too-large.click DiameterRatedSource 'the CODE argument must not exceed 0xFFFFFF: the Command Code field is three octets (RFC 6733 section 3)'
}

@test "rated-source-code-max: CODE 0xFFFFFF prints ffffff in a 20-octet message" {
	run_click rated-source-code-max.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# The inclusive ceiling in the second writer: Length still 20 and the code
	# ffffff, so the guard must be > rather than >=.
	local expected='^rated-source-code-max: +20 \| 01000014 80ffffff 0000002a [0-9a-f]{8} [0-9a-f]{8}$'
	[[ "$output" =~ $expected ]] || { echo "expected: 20 octets, Length 20, flags 80, code ffffff"; return 1; }
}

@test "rated-source-timing: the refill timer waits 1 ms in the bucket's own unit" {
	local out="$BATS_TEST_TMPDIR/rated-source-timing"
	run_click_simtime rated-source-timing.click "$out"
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# Print(TIMESTAMP true) renders "timing: SEC.SUBSEC:   20 | ...". The burst
	# is rate < 200 ? 2 : rate / 100, so RATE 1000 gives 10 tokens: the first
	# ten messages leave within a few nanoseconds of each other, and the
	# eleventh and twelfth each wait one tick for a token. The bucket ticks at
	# 1 ms in both builds -- jiffies at the default CLICK_HZ upstream,
	# microseconds in FastClick -- so the two intervals after the burst must
	# each fall in [0.5 ms, 5 ms]. A cast-only conversion reads FastClick's
	# microseconds as jiffies and schedules the timer 1 s out, and the window
	# rejects that as it rejects a zero interval.
	local frames gaps
	frames=$(grep -c '^timing:' "$out" || true)
	[ "$frames" -eq 12 ] || { echo "expected 12 timing lines, got $frames"; return 1; }
	gaps=$(awk '
		/^timing:/ {
			ts = $2
			sub(/:$/, "", ts)
			split(ts, part, ".")
			sec[++n] = part[1] + 0
			frac[n] = part[2] + 0
			digits = length(part[2])
		}
		END {
			# The two post-burst intervals: frames 10 to 11 and 11 to 12.
			# Splitting seconds from subseconds keeps the subtraction exact;
			# the epoch itself is far past the exact integer range of a double.
			scale = 1
			for (i = 0; i < digits; i++) scale *= 10
			for (i = 10; i <= 11; i++)
				printf "%.9f\n", (sec[i + 1] - sec[i]) + (frac[i + 1] - frac[i]) / scale
		}' "$out")
	local gap count=0
	while IFS= read -r gap; do
		awk -v gap="$gap" 'BEGIN { exit !(gap >= 0.0005 && gap <= 0.005) }' || {
			echo "expected a 1 ms refill interval, got ${gap}s"
			return 1
		}
		count=$((count + 1))
	done <<<"$gaps"
	[ "$count" -eq 2 ] || { echo "expected two intervals, got $count"; return 1; }
}

@test "randomness-encap: RandomSeed reproduces the identifiers across runs" {
	# The literal first frame pins the two seed draws and the number of draws the
	# writer consumes: 16d5a847 and 3328a195 are Click's random() output for
	# SEED 12345, so a moved stream or changed seed arithmetic fails here.
	expect_seeded randomness-encap.click 24 \
		'encap:   24 | 01000018 80000118 00000000 16d5a847 3328a195 deadbeef'
}

@test "randomness-rated-source: RandomSeed reproduces the identifiers across runs" {
	# Same two draws, same first frame: the first emitted message takes the
	# first two draws, so the token bucket has not consumed an identifier first.
	expect_seeded randomness-rated-source.click 20 \
		'rated-source:   20 | 01000014 80000118 0000002a 16d5a847 3328a195'
}

@test "randomness-push-avp: RandomSeed reproduces the generated value across runs" {
	expect_seeded randomness-push-avp.click 36
}

@test "randomness-push-avp-uint32: RandomSeed reproduces the generated value across runs" {
	expect_seeded randomness-push-avp-uint32.click 32
}

@test "randomness-rated-source-pull: RandomSeed reproduces the pull path's identifiers across runs" {
	# The literal first frame pins the draw order in pull(): a swap of the two
	# nextX() calls or an extra draw moves it.
	expect_seeded randomness-rated-source-pull.click 20 \
		'rated-source-pull:   20 | 01000014 80000118 0000002a 16d5a847 3328a195'
}

@test "identifiers-rated-source-pull-unique: a refused pull consumes no identifier" {
	# RATE 10 leaves refused pulls between the three returned packets, so a
	# counter advanced before remove_if(1) leaves a gap in the consecutive span.
	expect_identifier_run identifiers-rated-source-pull-unique.click 3
}

@test "identifiers-encap-unique: 240 000 messages carry distinct hop-by-hop and end-to-end values" {
	expect_unique_identifiers identifiers-encap-unique.click 240000
}

@test "identifiers-rated-source-unique: the same counts through the token bucket" {
	expect_unique_identifiers identifiers-rated-source-unique.click 240000
}

@test "identifiers-encap-wrap: the 2^20 end-to-end carry keeps both fields consecutive" {
	# One run only: 1 048 577 messages crosses the 20-bit boundary once, so the
	# high-order 12 bits must carry. Distinctness, string equality and the
	# consecutive span all fail if the low 20 bits are masked without carry.
	expect_identifier_run identifiers-encap-wrap.click 1048577
}

@test "identifiers-encap-drop-then-emit: a dropped packet consumes no identifier" {
	local out="$BATS_TEST_TMPDIR/drop-then-emit"
	run_click_simtime identifiers-encap-drop-then-emit.click "$out"
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# The 5-octet payload is refused before the counters, so the emitted frame
	# still carries the seed's first two draws. Advancing the counters before
	# the drop guard would print the second pair here. The simulated clock fixes
	# the two packets' order.
	local expected=$'DiameterEncap: dropping packet: the payload length is not a multiple of 4, so it cannot be a sequence of padded AVPs (RFC 6733 section 3)\nids:   24 | 01000018 80000118 00000000 16d5a847 3328a195 deadbeef'
	[ "$(cat "$out")" = "$expected" ] || { echo "expected: the drop line then the first-pair frame"; echo "got: $(cat "$out")"; return 1; }
}

@test "randomness-encap-push-avp: a seeded writer leaves the RAND* stream at a fixed position" {
	run_click randomness-encap-push-avp.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# Frame 1 carries the two seed draws, so the appended value is the third
	# draw; frame 2 carries the next counters and the next draw. A changed seed
	# arithmetic or a different number of draws per message moves these bytes.
	expect $'mix:   44 | 0100002c 80000118 00000000 16d5a847 3328a195 00000108 00000008 00000108 00000010 44423130 31453838\nmix:   44 | 0100002c 80000118 00000000 16d5a848 3328a196 00000108 00000008 00000108 00000010 42313935 45353230'
}

@test "popstorepush-roundtrip: unpadded AVP pop then push restores the message" {
	run_click popstorepush-roundtrip.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	expect $'out0:   32 | 01000020 80000118 00000000 00000001 00000002 00000108 0000000a 61620000\nout1:   44 | 0100002c 80000118 00000000 00000001 00000002 00000108 0000000a 61620000 0000010c 0000000a 78790000'
}

@test "popstorepush-mandatory: an M=1 AVP survives decode and re-encode" {
	run_click popstorepush-mandatory.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# The first pass pops the AVP (output 0, 20 octets); the second pushes the
	# stored AVP back, and output 1 carries it again with flags 40.
	expect $'out0:   20 | 01000014 80000118 00000000 00000001 00000002\nout1:   44 | 0100002c 80000118 00000000 00000001 00000002 00000108 4000000b 61626300 00000108 4000000b 61626300'
}

@test "popstorepush-length-overflow: a stored AVP that would exceed 0xFFFFFF is dropped" {
	run_click popstorepush-length-overflow.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# The maximal appends make Click print its put advisory; the Print line is the
	# popped 20-octet header and the only other line is the drop.
	local printed others
	printed=$(grep '^out0:' <<<"$output")
	others=$(grep -v '^out0:' <<<"$output" | grep -v '^expensive Packet::put' || true)
	[ "$others" = 'DiameterPopStorePushAVP: dropping packet: pushing the stored AVP would exceed the three-octet Length field (RFC 6733 section 3)' ] || { echo "unexpected output: $others"; return 1; }
	[[ "$printed" =~ ^out0:\ +20\ \|\ 01000014\ 80000118\ 00000000\ 00000001\ 00000002$ ]] || { echo "expected: out0 20 octets"; return 1; }
}

@test "popstorepush-store-retained: an overflow drop keeps the stored AVP for a later packet" {
	local out="$BATS_TEST_TMPDIR/store-retained"
	run_click_simtime popstorepush-store-retained.click "$out"
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	# Packet 1 arms the store (out0 is the popped 20-octet header), packet 2 is
	# dropped because it cannot hold the stored maximal AVP, and packet 3 carries
	# it on output 1. A drop that clears the store fails the out1 line. The
	# simulated clock fixes the three packets' order.
	local output printed others
	output=$(cat "$out")
	printed=$(grep '^out1:' <<<"$output")
	others=$(grep -v '^out0:' <<<"$output" | grep -v '^out1:' | grep -v '^expensive Packet::put' || true)
	[ "$others" = 'DiameterPopStorePushAVP: dropping packet: pushing the stored AVP would exceed the three-octet Length field (RFC 6733 section 3)' ] || { echo "unexpected output: $others"; return 1; }
	[[ "$output" =~ out0:\ +20\ \|\ 01000014\ 80000118\ 00000000\ 00000001\ 00000002 ]] || { echo "expected: out0 20 octets"; return 1; }
	[[ "$printed" =~ ^out1:\ +16777212\ \|\ 01fffffc\ 80000118\ 00000000\ 00000001\ 00000002\ 00000108\ 00ffffe8\ [0-9a-f]{8}\ [0-9a-f]{8}$ ]] || { echo "expected: out1 carries the stored AVP on a 16,777,212-octet message"; return 1; }
}

@test "malformed-version-decap: Version 2 dropped by DiameterDecap, no payload forwarded" {
	run_click malformed-version-decap.click
	# A-5: RFC 6733 section 3 fixes the Version at 1.
	expect_drop DiameterDecap 'the Version field is not 1'
}

@test "malformed-version-pushavp: Version 2 dropped by DiameterPushAVP" {
	run_click malformed-version-pushavp.click
	# The frame is not appended to and re-emitted with its bogus Version.
	expect_drop DiameterPushAVP 'the Version field is not 1'
}

@test "malformed-version-popavp: Version 2 dropped by DiameterPopAVP" {
	run_click malformed-version-popavp.click
	expect_drop DiameterPopAVP 'the Version field is not 1'
}

@test "malformed-version-popstorepush: Version 2 dropped by DiameterPopStorePushAVP" {
	run_click malformed-version-popstorepush.click
	# Neither output sees a packet.
	expect_drop DiameterPopStorePushAVP 'the Version field is not 1'
}

@test "malformed-version-flip-request: Version 2 dropped by DiameterFlipRequest" {
	run_click malformed-version-flip-request.click
	expect_drop DiameterFlipRequest 'the Version field is not 1'
}

@test "malformed-version-length: the Version reason wins over the Length reason" {
	run_click malformed-version-length.click
	# The version test runs before the Length comparison, so a frame with both
	# faults reports the Version reason. Moving it after the Length check fails
	# here.
	expect_drop DiameterDecap 'the Version field is not 1'
}

@test "malformed-version-short: the Version reason wins over the short-header reason" {
	run_click malformed-version-short.click
	# A 3-octet frame with first octet 02. The version test runs before the
	# short-header guard, so moving it below that guard fails here.
	expect_drop DiameterDecap 'the Version field is not 1'
}

@test "malformed-empty-packet: a zero-octet packet reports the short header" {
	run_click malformed-empty-packet.click
	# The one-octet guard keeps the Version test from reading past an empty
	# buffer; without it this packet would report a bad Version.
	expect_drop DiameterDecap 'packet shorter than the 20-octet Diameter header'
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

@test "malformed-avpdecap-vendor-id-zero: V set with Vendor-Id 0 dropped by DiameterAvpDecap" {
	run_click malformed-avpdecap-vendor-id-zero.click
	# A-6: the 12-octet header is present and its Length agrees, but RFC 6733
	# section 4.1.1 forbids Vendor-Id zero with V set.
	expect_drop DiameterAvpDecap 'the V bit is set with a zero Vendor-Id'
}

@test "malformed-avpdecap-vendor-id-zero-length: a Length fault outranks the Vendor-Id reason" {
	run_click malformed-avpdecap-vendor-id-zero-length.click
	# The AVP has V set, Vendor-Id 0 and Length 8, below its 12-octet header.
	# Structural checks run first, so hoisting the Vendor-Id test above them
	# fails here.
	expect_drop DiameterAvpDecap 'AVP length below its header'
}

@test "malformed-avp-in-message-vendor-id-zero: V set with Vendor-Id 0 dropped by DiameterPopAVP" {
	run_click malformed-avp-in-message-vendor-id-zero.click
	# The offending AVP is the second in a two-AVP message, so the shared check
	# must run at every offset, not only at the first AVP.
	expect_drop DiameterPopAVP 'the V bit is set with a zero Vendor-Id'
}

@test "malformed-avp-in-message-pushavp-vendor-id-zero: the same AVP dropped by DiameterPushAVP" {
	run_click malformed-avp-in-message-pushavp-vendor-id-zero.click
	# DiameterPushAVP validates the message before appending, so it inherits the
	# check without an edit of its own.
	expect_drop DiameterPushAVP 'the V bit is set with a zero Vendor-Id'
}

@test "malformed-avp-in-message-popstorepush-vendor-id-zero: the same AVP dropped by DiameterPopStorePushAVP" {
	run_click malformed-avp-in-message-popstorepush-vendor-id-zero.click
	# The pop-store-push element walks the message with the same check and drops
	# before storing, so neither output sees a packet.
	expect_drop DiameterPopStorePushAVP 'the V bit is set with a zero Vendor-Id'
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

@test "malformed-avp-padding-overhang: an unaligned Length outranks the padded AVP bound" {
	run_click malformed-avp-padding-overhang.click
	# A-4: the 30-octet frame declares 30, which is not a multiple of 4, so the
	# header's alignment rule drops it before the AVP walk. The padded-bound
	# guard that the frame was built for is now unreachable defence in depth.
	expect_drop DiameterPopAVP 'the Length field is not a multiple of 4'
}

@test "malformed-avp-trailing-octets: partial trailing AVP header dropped by DiameterPopAVP" {
	run_click malformed-avp-trailing-octets.click
	# A-4: the frame is 32 octets with four trailing octets, so its aligned
	# Length passes the header rule and the walk still reaches the partial
	# second header, which is the branch this config pins.
	expect_drop DiameterPopAVP 'packet shorter than the 8-octet AVP header'
}

@test "malformed-length-not-aligned: an unaligned Length dropped by DiameterDecap" {
	run_click malformed-length-not-aligned.click
	# A-4: the 25-octet frame is exactly what the pre-change DiameterEncap
	# emitted for a 5-octet payload. RFC 6733 section 3 makes the Message Length
	# a multiple of 4, so it is dropped and no payload is forwarded.
	expect_drop DiameterDecap 'the Length field is not a multiple of 4'
}

@test "malformed-length-not-aligned-pushavp: the same frame dropped by DiameterPushAVP" {
	run_click malformed-length-not-aligned-pushavp.click
	# A rewriter inherits the header rule, so it drops the frame instead of
	# appending to it and re-emitting the unaligned Length.
	expect_drop DiameterPushAVP 'the Length field is not a multiple of 4'
}

@test "malformed-length-not-aligned-mismatch: the alignment reason outranks the mismatch" {
	run_click malformed-length-not-aligned-mismatch.click
	# A 24-octet packet whose Length says 25 carries both faults. The alignment
	# test runs before the comparison, so moving it below the mismatch check
	# fails here.
	expect_drop DiameterDecap 'the Length field is not a multiple of 4'
}

@test "malformed-version-not-aligned: the Version reason outranks the alignment" {
	run_click malformed-version-not-aligned.click
	# Version 2 and Length 25 in one frame. The Version test runs first, so a
	# hoisted alignment test fails here.
	expect_drop DiameterDecap 'the Version field is not 1'
}

@test "malformed-short-not-aligned: the short-header reason outranks the alignment" {
	run_click malformed-short-not-aligned.click
	# A 10-octet frame declaring 25. The short-header guard runs before the
	# alignment test, which also keeps the three-octet parse in bounds.
	expect_drop DiameterDecap 'packet shorter than the 20-octet Diameter header'
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

@test "malformed-error-on-request: E on a request dropped by DiameterDecap" {
	run_click malformed-error-on-request.click
	expect_drop DiameterDecap 'the E bit is set on a request'
}

@test "malformed-error-on-request-message: E on a request dropped by DiameterPopAVP" {
	run_click malformed-error-on-request-message.click
	expect_drop DiameterPopAVP 'the E bit is set on a request'
}

@test "malformed-retransmit-on-answer: T on an answer dropped by DiameterFlipRequest" {
	run_click malformed-retransmit-on-answer.click
	expect_drop DiameterFlipRequest 'the T bit is set on an answer'
}

@test "malformed-error-on-request-push: E on a request dropped by DiameterPushAVP" {
	run_click malformed-error-on-request-push.click
	expect_drop DiameterPushAVP 'the E bit is set on a request'
}

@test "malformed-retransmit-on-answer-popstorepush: T on an answer dropped by DiameterPopStorePushAVP" {
	run_click malformed-retransmit-on-answer-popstorepush.click
	expect_drop DiameterPopStorePushAVP 'the T bit is set on an answer'
}

@test "malformed-error-on-request-length: the Length reason wins over the flag reason" {
	run_click malformed-error-on-request-length.click
	# The flag test runs only after the Length matches, so a frame with both
	# faults reports the Length reason. Hoisting the flag test above the Length
	# comparison fails here.
	expect_drop DiameterDecap 'header Length does not match packet length'
}

@test "no-avp: header-only message forwarded unchanged by both pop elements" {
	run_click no-avp.click
	[ "$status" -eq 0 ] || { echo "click exit $status"; return 1; }
	expect $'pop-avp:   20 | 01000014 80000118 00000000 00000001 00000002\npop-store-push:   20 | 01000014 80000118 00000000 00000001 00000002'
}

@test "randomness-source: no element calls srand, rand, srandom, random, click_srandom or click_random_srandom" {
	# F-11 lives in configure(), which no byte assertion can see. Ban every
	# reseed form (click_srandom, click_random_srandom) and every bare C RNG
	# call (srand, rand, srandom, random); draining the stream through
	# click_random() is the only allowed use. A word boundary keeps the bare
	# forms from matching click_random().
	local src="$BATS_TEST_DIRNAME/../src"
	[ -d "$src" ] || { echo "missing source directory: $src"; return 1; }
	local hits status=0
	hits=$(grep -rnE '\b(s?rand|s?random|click_srandom|click_random_srandom)[[:space:]]*\(' "$src") || status=$?
	# grep exits 1 when it finds nothing, which is the pass case. Exit 2 is an
	# unreadable tree and must not be mistaken for a clean scan.
	[ "$status" -le 1 ] || { echo "could not scan $src (grep exit $status)"; return 1; }
	[ -z "$hits" ] || { echo "banned RNG call in src/: $hits"; return 1; }
}
