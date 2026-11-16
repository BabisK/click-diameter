#!/usr/bin/env bats
#
# Package identity and source hygiene assertions.
#
#   bats --tap tests
#
# These read the tree instead of a running router: configure.ac, and every
# header and source under src/. Only the identity check needs a tool, autoconf,
# which the build recipe already requires; no Click binary or installed prefix
# is involved. A source-level assertion exists because none of these defects is
# visible to a byte assertion -- a stale include guard, an unused <iostream>
# include and a shadowed Click hook all leave the emitted packets byte for byte
# identical, so only a scan of the tree catches a regression. Each test names
# the finding it pins.

src=$BATS_TEST_DIRNAME/../src

# declares FILE NAME -- print 1 when FILE declares a member function NAME, and 0
# when it does not. Only a declaration counts: a call (`NAME(p);`), a statement
# (`p = NAME(p);`), an inline body (`{ return NAME(p); }`) and a prose mention in
# a comment are not declarations. A trailing CR from a Windows checkout is
# stripped first, so the same tree passes under either line ending.
declares() {
	awk -v name="$2" '
		{
			sub(/\r$/, "")
			if ($0 ~ /^[[:space:]]*(\/\/|\*|\/\*)/)
				next
			if ($0 !~ ("(^|[^A-Za-z0-9_])" name "[[:space:]]*\\("))
				next
			if ($0 !~ /;[[:space:]]*$/)
				next
			if ($0 ~ /[{}]/)
				next
			if ($0 ~ /(^|[^A-Za-z0-9_])(return|=|->|\.)/)
				next
			if ($0 ~ ("^[[:space:]]*" name "[[:space:]]*\\("))
				next
			found = 1
		}
		END { print (found ? 1 : 0) }
	' "$1"
}

@test "package-identity: configure.ac names click-diameter 2.1 (F-14)" {
	command -v autoconf >/dev/null 2>&1 || skip "autoconf is not installed"
	local work="$BATS_TEST_TMPDIR/identity"
	local source="$BATS_TEST_DIRNAME/../configure.ac"
	[ -f "$source" ] || { echo "missing configure.ac: $source"; return 1; }
	mkdir -p "$work"
	cp "$source" "$work/configure.ac" \
		|| { echo "could not copy $source"; return 1; }
	local version first
	# Autoconf 2.72 warns that AC_OUTPUT should be called without arguments on
	# configure.ac:73. That warning is pre-existing and unrelated to identity,
	# so stderr is dropped and only the version line is read.
	version=$(cd "$work" && autoconf 2>/dev/null && ./configure --version 2>/dev/null) \
		|| { echo "autoconf or configure --version failed"; return 1; }
	first=${version%%$'\n'*}
	[ "$first" = "click-diameter configure 2.1" ] || {
		echo "expected: click-diameter configure 2.1"
		echo "got: $first"
		return 1
	}
}

@test "guard-match: every src/*.hh guard matches its filename (F-15)" {
	local file stem guard bad
	for file in "$src"/*.hh; do
		[ -f "$file" ] || { echo "missing source headers in $src"; return 1; }
		stem=$(basename "$file" .hh | tr '[:lower:]' '[:upper:]')
		guard="${stem}_HH_"
		# One pass per header: the first #ifndef and #define must both name the
		# guard, and the last #endif must carry it as its comment. A guard that
		# drifts from the filename, or an #endif comment left on the element's
		# former name, prints a line and fails the test. A trailing CR from a
		# Windows checkout is stripped before the comparison.
		bad=$(awk -v guard="$guard" '
			{ sub(/\r$/, ""); $0 = $0 }
			$1 == "#ifndef" && !seen_ifndef++ {
				if ($2 != guard)
					print "line " NR ": #ifndef " $2 " should be " guard
			}
			$1 == "#define" && !seen_define++ {
				if ($2 != guard)
					print "line " NR ": #define " $2 " should be " guard
			}
			$1 == "#endif" { endif_line = NR; endif_text = $0 }
			END {
				if (!seen_ifndef)
					print "no #ifndef guard"
				if (!seen_define)
					print "no #define guard"
				if (endif_text != "#endif /* " guard " */")
					print "line " endif_line ": " endif_text \
						" should be #endif /* " guard " */"
			}
		' "$file") || { echo "could not read $file"; return 1; }
		[ -z "$bad" ] || { echo "$file: $bad"; return 1; }
	done
}

@test "no-iostream: no file under src/ includes <iostream> (F-15)" {
	local hits status=0
	hits=$(grep -rnE '^[[:space:]]*#[[:space:]]*include[[:space:]]*<iostream>' "$src") || status=$?
	# grep exits 1 when it finds nothing, which is the pass case. Exit 2 is an
	# unreadable tree and must not be mistaken for a clean scan.
	[ "$status" -le 1 ] || { echo "could not scan $src (grep exit $status)"; return 1; }
	[ -z "$hits" ] || { echo "iostream include in src/: $hits"; return 1; }
}

@test "no-dead-hook: no header declares simple_action beside push (F-15)" {
	local file push simple
	local headers
	headers=$(find "$src" -type f -name '*.hh') \
		|| { echo "could not scan $src"; return 1; }
	[ -n "$headers" ] || { echo "missing source headers in $src"; return 1; }
	for file in $headers; do
		push=$(declares "$file" push) || { echo "could not read $file"; return 1; }
		simple=$(declares "$file" simple_action) \
			|| { echo "could not read $file"; return 1; }
		# Element::push calls simple_action, so an element that overrides push
		# itself makes its own simple_action unreachable: nothing outside the
		# element can call it, and Click never will.
		if [ "$push" -eq 1 ] && [ "$simple" -eq 1 ]; then
			echo "$file: declares simple_action beside push, which Click never calls"
			return 1
		fi
	done
}
