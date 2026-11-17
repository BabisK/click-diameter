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
# in src/diameter.* is. An access inside a Click header that the compiler inlined
# into this package is attributed to click/string.hh and marked (diameter.uo+) on
# that same frame, so the module suffix is a package frame too: without it a
# shared-String race is reported as Click code and ignored.
#
# Click's Spinlock is the one Click header whose races are the lock itself:
# click/sync.hh and the click/atomic.hh it is built from use an inline-assembly
# xchg loop that the sanitizer cannot see, so the lock's own _lock, _owner and
# _depth accesses are reported as races although the xchg orders them on every
# architecture Click supports. Those frames are Click core, not package state.
# A report is therefore ignored only when its racing #0 access is in those two
# headers and the same report's stack names Spinlock::; every other report is
# judged on its package frames as before, so an element that holds a Spinlock
# announces the critical section to the sanitizer (__tsan_acquire/
# __tsan_release) and a race on the data the lock protects is still reported on
# the element's own line and still fails here.
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
		function flush() {
			if (package_frame != "" && !(first0 ~ /include\/click\/(sync|atomic)\.hh:/ && report ~ /Spinlock::/))
				printf "%s", package_frame
			package_frame = ""
			first0 = ""
			report = ""
		}
		/^WARNING: ThreadSanitizer: data race/ {
			flush()
			inreport = 1
			report = $0 "\n"
			next
		}
		/^SUMMARY: ThreadSanitizer/ {
			flush()
			inreport = 0
			next
		}
		inreport {
			report = report $0 "\n"
			if (/^ *#0 /) {
				if (first0 == "")
					first0 = $0
				if (/src\/diameter[^ ]*:/ || /\(diameter\.uo\+/)
					package_frame = package_frame $0 "\n"
			}
		}
		END { flush() }
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
