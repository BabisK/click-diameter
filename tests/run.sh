#!/bin/sh
# Run the smoke configs against an installed Click that carries this package.
#
#   tests/run.sh              # uses 'click' from PATH
#   tests/run.sh ~/click/bin/click
#
# The configs under configs/ must all exit 0. The repros under known-defects/
# are intentionally left out: they exercise defects still listed in
# _bmad-output/specs/spec-diameter-package-hardening/findings.md, so several of
# them abort or hang today. Run one by hand to see the current behavior.

set -u

click=${1:-click}
here=$(dirname "$0")
status=0

if ! command -v "$click" >/dev/null 2>&1; then
	echo "error: '$click' not found; pass the path to a click binary that has this package installed" >&2
	exit 2
fi

for cfg in "$here"/configs/*.click; do
	name=$(basename "$cfg")
	if command -v timeout >/dev/null 2>&1; then
		out=$(timeout 10 "$click" "$cfg" 2>&1)
	else
		out=$("$click" "$cfg" 2>&1)
	fi
	rc=$?
	if [ $rc -eq 0 ]; then
		echo "PASS $name"
	else
		echo "FAIL $name (exit $rc)"
		echo "$out" | sed 's/^/     /'
		status=1
	fi
done

exit $status
