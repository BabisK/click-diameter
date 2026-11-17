/*
 * diameterconf.hh -- shared configuration checks for the Diameter elements
 * Charalampos "Babis" Kaidos
 */

#ifndef DIAMETERCONF_HH_
#define DIAMETERCONF_HH_

#include <stddef.h>
#include <string.h>
#include <click/vector.hh>
#include <click/string.hh>
#include <click/error.hh>
CLICK_DECLS

// Rejects a keyword that appears twice in an element's configuration. Click's
// Args keeps the last occurrence, so a repeat silently discards the earlier
// value; every argument in this package is a keyword followed by exactly one
// value (Click rejects a bare boolean), so a repeat is a caller error rather
// than a second value source.
//
// Click hands configure() one comma-separated argument per vector element, with
// the keyword and its value separated by whitespace ("CODE 280"), so the first
// word of each element is the keyword. An element whose first word is not one of
// this element's keywords is a positional argument or an argument Args will
// reject; it is ignored here. Returns 0 when there is no repeat, or -1 after
// reporting the first one.
inline int diameter_reject_duplicate_keywords(const Vector<String> &conf,
		ErrorHandler *errh, const char *const *keywords, size_t count)
{
	// The largest keyword table in this package has eleven entries.
	bool seen[16] = { false };
	for (int i = 0; i < conf.size(); ++i) {
		const char *s = conf[i].c_str();
		const char *end = s;
		while (*end && *end != ' ' && *end != '\t')
			++end;
		const size_t len = (size_t) (end - s);
		size_t k = 0;
		for (; k < count; ++k)
			if (strlen(keywords[k]) == len && memcmp(s, keywords[k], len) == 0)
				break;
		if (k == count)
			continue;
		if (seen[k])
			return errh->error("the %.*s argument is given more than once",
					(int) len, s);
		seen[k] = true;
	}
	return 0;
}

CLICK_ENDDECLS
#endif /* DIAMETERCONF_HH_ */
