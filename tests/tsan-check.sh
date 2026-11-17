#!/usr/bin/env bash
#
# tests/tsan-check.sh CLICK CONFIG...
#
# Runs each config on two router threads under a Click built with
# ThreadSanitizer and fails when a racing memory access happens inside this
# package. The counterpart to the frame-level smp-* tests: those can see a
# Length that disagrees with its frame, while a shared String or header field
# only shows up as a data race.
#
# A ThreadSanitizer report's first stack frame is the racing memory access, so
# only the frames of that access are judged. Click core races its own
# bookkeeping on shutdown (Master, RouterThread, Discard), so those reports are
# expected and are not this package's business; anything whose access frame is
# in src/diameter.* is.
#
# Expects a Click and a package that were both built with -fsanitize=thread.
# Exits 0 when every config ran and no package frame raced, 1 on a race or a
# failed run, 2 on a usage or build error.

set -u

if [ "$#" -lt 2 ]; then
	echo "usage: $0 CLICK CONFIG..." >&2
	exit 2
fi

click=$1
shift

prefix=$(cd "$(dirname "$click")/.." && pwd)
module=$(ls "$prefix"/lib/diameter.uo 2>/dev/null | head -1)
if [ -z "$module" ]; then
	echo "FAIL: no diameter.uo under $prefix/lib; install the package there first" >&2
	exit 2
fi
if command -v ldd >/dev/null 2>&1 && ! ldd "$module" | grep -q 'libtsan'; then
	echo "FAIL: $module is not built with ThreadSanitizer, so it cannot report a race" >&2
	echo "      rebuild the package with CXXFLAGS=\"-fsanitize=thread -g -O1 -fPIC -shared\"" >&2
	exit 2
fi

status=0
for config in "$@"; do
	out=$(mktemp)
	# halt_on_error=0 keeps the run going after Click core's own reports, and
	# exitcode=0 makes a clean run exit 0. A non-zero status is then a crash or
	# a configuration failure worth seeing.
	TSAN_OPTIONS="halt_on_error=0:exitcode=0" timeout 300 "$click" -j 2 "$config" >"$out" 2>&1
	rc=$?

	if [ "$rc" -ne 0 ]; then
		echo "FAIL $config: click exited $rc under ThreadSanitizer"
		tail -20 "$out"
		status=1
		rm -f "$out"
		continue
	fi

	# Frames reach stderr, so the run above captured them. Without one the
	# script would certify a run that never pushed a packet.
	if ! grep -qE '^[a-z0-9-]+: +[0-9]+ \| ' "$out"; then
		echo "FAIL $config: no frame was printed, so the run proved nothing"
		status=1
		rm -f "$out"
		continue
	fi

	races=$(awk '
		/^SUMMARY: ThreadSanitizer/ { inreport = 0 }
		/ThreadSanitizer: data race/ { inreport = 1 }
		inreport && /^ *#0 / && /src\/diameter[^ ]*:/ { print }
	' "$out")

	if [ -n "$races" ]; then
		echo "FAIL $config: a racing memory access is inside this package:"
		printf '%s\n' "$races" | sed 's/^ */  /'
		status=1
	else
		echo "ok $config"
	fi
	rm -f "$out"
done

exit "$status"
