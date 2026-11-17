#!/usr/bin/env bats
#
# Man page assertions over an installed prefix.
#
#   bats --tap tests                              # click from PATH
#   CLICK=~/click/bin/click bats --tap tests      # explicit binary
#
# Requires a Click prefix that already carries this package: `make install`
# renders one page per element from the `=c`/`=d` blocks in src/, so a header
# whose documentation is missing or stale fails here instead of passing
# silently. The prefix is read from the Click binary, because that is the
# prefix `require(diameter)` and `make install` both write to:
#
#   PREFIX/bin/click  ->  PREFIX/share/man/man7
#
# A prefix that is not on MANPATH is read with `man -M PREFIX/share/man`.

click=${CLICK:-click}

# click_binary -- the absolute path of the Click binary under test.
click_binary() {
	local path
	path=$(command -v "$click") || {
		echo "click not found: $click" >&2
		return 1
	}
	readlink -f "$path" || {
		echo "cannot resolve $path" >&2
		return 1
	}
}

# man7_dir -- PREFIX/share/man/man7 for the Click binary's prefix.
man7_dir() {
	local binary
	binary=$(click_binary) || return 1
	echo "$(dirname "$(dirname "$binary")")/share/man/man7"
}

# page NAME -- the nroff text of NAME.7click.gz, or a failure if it is absent.
page() {
	local dir file
	dir=$(man7_dir) || return 1
	file="$dir/$1.7click.gz"
	[ -f "$file" ] || { echo "missing man page: $file"; return 1; }
	# The element list is written uncompressed beside the gzipped element
	# pages, so -f passes both through.
	zcat -f "$file"
}

# section NAME -- the nroff section NAME read from stdin, up to the next .SH
# heading.
section() {
	awk -v heading=".SH \"$1\"" '
		$0 == heading { inside = 1; next }
		inside && index($0, ".SH \"") == 1 { inside = 0 }
		inside { print }
	'
}

# expect_element_page ELEMENT [ARGUMENT...] -- the page names the element in
# its SYNOPSIS, carries the generated Ports, Processing and Package lines, has
# a non-empty DESCRIPTION, and names every ARGUMENT in both the SYNOPSIS and
# the DESCRIPTION. A page missing its `=c` block fails at the SYNOPSIS check; a
# stale one fails on the argument that its header no longer parses.
expect_element_page() {
	local element="$1" text synopsis description arg
	shift
	text=$(page "$element") || return 1
	synopsis=$(section SYNOPSIS <<<"$text")
	description=$(section DESCRIPTION <<<"$text")

	grep -qF "$element" <<<"$synopsis" || {
		echo "$element: SYNOPSIS does not name the element"
		return 1
	}
	grep -qF '\fBPorts\fR: ' <<<"$synopsis" || {
		echo "$element: SYNOPSIS has no Ports line"
		return 1
	}
	grep -qF '\fBProcessing\fR: ' <<<"$synopsis" || {
		echo "$element: SYNOPSIS has no Processing line"
		return 1
	}
	grep -qF '\fBPackage\fR: diameter' <<<"$synopsis" || {
		echo "$element: SYNOPSIS does not say Package: diameter"
		return 1
	}
	[ -n "$(tr -d '[:space:]' <<<"$description")" ] || {
		echo "$element: DESCRIPTION is empty"
		return 1
	}

	for arg in "$@"; do
		grep -qwF "$arg" <<<"$synopsis" || {
			echo "$element: SYNOPSIS does not name the $arg argument"
			return 1
		}
		grep -qF ".IP \"$arg\"" <<<"$description" || {
			echo "$element: DESCRIPTION does not document the $arg argument"
			return 1
		}
	done
}

@test "manpages: nine element pages and the package element list are installed" {
	local dir count
	dir=$(man7_dir) || return 1
	count=$(find "$dir" -maxdepth 1 -type f -name 'Diameter*.7click.gz' | wc -l)
	[ "$count" -eq 9 ] || {
		echo "expected 9 Diameter*.7click.gz pages in $dir, found $count"
		return 1
	}
	[ -f "$dir/elements-diameter.7click.gz" ] || {
		echo "missing $dir/elements-diameter.7click.gz"
		return 1
	}
}

@test "manpages: DiameterRatedSource documents its page and its seven arguments" {
	expect_element_page DiameterRatedSource CODE REQUEST RATE LIMIT ACTIVE APPID STOP
}

@test "manpages: DiameterEncap documents its page and its six arguments" {
	expect_element_page DiameterEncap CODE REQUEST ERROR PROXIABLE RETRANSMITED APPID
}

@test "manpages: DiameterPushAVP documents its page and its eleven arguments" {
	expect_element_page DiameterPushAVP CODE VENDORSPEC VENDOR MANDATORY OCTETSTRING \
		UINT32 RANDUINT32 RANDALPHANUMSTRING RANDNUMSTRING RANDALPHASTRING RANDHEXSTRING
}

@test "manpages: DiameterAvpEncap documents its page and its three arguments" {
	expect_element_page DiameterAvpEncap CODE VENDORID MANDATORY
}

@test "manpages: DiameterDecap documents its page without arguments" {
	expect_element_page DiameterDecap
}

@test "manpages: DiameterPopAVP documents its page without arguments" {
	expect_element_page DiameterPopAVP
}

@test "manpages: DiameterPopStorePushAVP documents its page without arguments" {
	expect_element_page DiameterPopStorePushAVP
}

@test "manpages: DiameterFlipRequest documents its page without arguments" {
	expect_element_page DiameterFlipRequest
}

@test "manpages: DiameterAvpDecap documents its page without arguments" {
	expect_element_page DiameterAvpDecap
}

@test "manpages: the six readers document their drop path" {
	local element text description
	for element in DiameterDecap DiameterAvpDecap DiameterFlipRequest \
	    DiameterPushAVP DiameterPopAVP DiameterPopStorePushAVP; do
		text=$(page "$element") || return 1
		description=$(section DESCRIPTION <<<"$text")
		grep -qF 'dropping malformed packet' <<<"$description" || {
			echo "$element: DESCRIPTION does not name the drop path"
			return 1
		}
	done
	# A-5: the five readers that take a message name the bad-Version reason, so a
	# doc-only regression in the new drop path fails here. DiameterAvpDecap is
	# not one of them: an AVP carries no Version field. The page keeps the
	# header's line breaks, so flatten the description before matching.
	for element in DiameterDecap DiameterFlipRequest DiameterPushAVP \
	    DiameterPopAVP DiameterPopStorePushAVP; do
		text=$(page "$element") || return 1
		description=$(section DESCRIPTION <<<"$text")
		local flat=${description//$'\n'/ }
		grep -qF 'the Version field is not 1' <<<"$flat" || {
			echo "$element: DESCRIPTION does not name the bad-Version reason"
			return 1
		}
		# A-4: the same five readers reject a Length that is not a multiple of
		# 4, and the page is where a caller learns that rule. The bullet and
		# prose forms say "its Length field", so match the rule rather than
		# the full reason string.
		grep -qF 'not a multiple of 4' <<<"$flat" || {
			echo "$element: DESCRIPTION does not name the unaligned-Length rule"
			return 1
		}
	done
}

@test "manpages: the writers document the Command Code range and the append drop" {
	local element text description flat
	for element in DiameterEncap DiameterRatedSource; do
		text=$(page "$element") || return 1
		description=$(section DESCRIPTION <<<"$text")
		grep -qF '0xFFFFFF' <<<"$description" || {
			echo "$element: DESCRIPTION does not state the Command Code ceiling"
			return 1
		}
	done
	# A-4: the Encap page is where a caller learns that the writer pads the
	# payload and counts the pad in the Length.
	text=$(page DiameterEncap) || return 1
	description=$(section DESCRIPTION <<<"$text")
	flat=${description//$'\n'/ }
	grep -qF 'zero-padded up to a 4-octet boundary' <<<"$flat" || {
		echo "DiameterEncap: DESCRIPTION does not state the payload padding"
		return 1
	}
	# The page keeps the header's line breaks, so flatten the description
	# before matching the reason, as the bad-Version check above does.
	text=$(page DiameterPushAVP) || return 1
	description=$(section DESCRIPTION <<<"$text")
	flat=${description//$'\n'/ }
	grep -qF 'appending the AVP would exceed the three-octet Length field' <<<"$flat" || {
		echo "DiameterPushAVP: DESCRIPTION does not name the append drop"
		return 1
	}
}

@test "manpages: the two writers document the seeded identifier counters" {
	local element text description flat
	for element in DiameterEncap DiameterRatedSource; do
		text=$(page "$element") || return 1
		description=$(section DESCRIPTION <<<"$text")
		# The page keeps the header's line breaks, so flatten the description
		# before matching the prose. The seeding rule and the in-run uniqueness
		# guarantee are the only place a caller learns what RandomSeed buys.
		flat=${description//$'\n'/ }
		grep -qF 'seeded once from click_random()' <<<"$flat" || {
			echo "$element: DESCRIPTION does not name the identifier seeding rule"
			return 1
		}
		grep -qF 'unique for the first 2^32 messages of a run' <<<"$flat" || {
			echo "$element: DESCRIPTION does not state in-run identifier uniqueness"
			return 1
		}
	done
}

@test "manpages: the two pop elements document the no-AVP no-op" {
	local element text description
	for element in DiameterPopAVP DiameterPopStorePushAVP; do
		text=$(page "$element") || return 1
		description=$(section DESCRIPTION <<<"$text")
		grep -qF 'carries no AVPs' <<<"$description" || {
			echo "$element: DESCRIPTION does not state the no-AVP no-op"
			return 1
		}
	done
}

@test "manpages: DiameterRatedSource lists its five handlers with their kinds" {
	local text handlers name kind
	text=$(page DiameterRatedSource) || return 1
	handlers=$(section 'ELEMENT HANDLERS' <<<"$text")
	while read -r name kind; do
		grep -qF ".IP \"\fB$name\fR ($kind)\" 5" <<<"$handlers" || {
			echo "ELEMENT HANDLERS does not list $name ($kind)"
			return 1
		}
	done <<'EOD'
rate read/write
limit read/write
active read/write
count read-only
reset write-only
EOD
}

# expect_listed LIST ELEMENT -- LIST files ELEMENT under one of the three known
# categories, in its BY FUNCTION section, and gives it a non-empty summary line
# after its .M entry. The alphabetical list has no headings, so the scan stops
# there; an element that only survives in it has lost its category entry.
expect_listed() {
	awk -v element="$2" '
		/^\.SH "ALPHABETICAL LIST"/ { exit }
		/^\.SS "/ {
			section = $0
			sub(/^\.SS "/, "", section)
			sub(/"$/, "", section)
			next
		}
		element_found && !summary_checked {
			summary = $0
			summary_checked = 1
		}
		$0 == ".M " element " 7" {
			element_found = 1
			element_section = section
			next
		}
		END {
			if (!element_found) {
				print "not listed under a category" > "/dev/stderr"
				exit 1
			}
			if (element_section != "Basic Sources and Sinks" \
			    && element_section != "Basic Packet Transfer" \
			    && element_section != "Basic Packet Modification") {
				print "filed under \"" element_section "\"" > "/dev/stderr"
				exit 1
			}
			if (summary == "" || summary ~ /^\./) {
				print "no summary line" > "/dev/stderr"
				exit 1
			}
		}
	' <<<"$1"
}

@test "manpages: the element list files all nine under a known category with a summary" {
	local list element
	list=$(page elements-diameter) || return 1
	for element in DiameterAvpDecap DiameterAvpEncap DiameterDecap DiameterEncap \
	    DiameterFlipRequest DiameterPopAVP DiameterPopStorePushAVP DiameterPushAVP \
	    DiameterRatedSource; do
		expect_listed "$list" "$element" || {
			echo "elements-diameter: $element is not filed correctly"
			return 1
		}
	done
}