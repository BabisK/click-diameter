/*
 * diameterpushavp.{cc,hh} -- element that puts an AVP at the end of the packet
 * Charalampos "Babis" Kaidos
 */

#ifndef DIAMETERPUSHAVP_HH_
#define DIAMETERPUSHAVP_HH_
#include <click/element.hh>
#include "diameter.hh"
CLICK_DECLS

/*
=c

DiameterPushAVP(CODE [, VENDORSPEC, VENDOR, MANDATORY, OCTETSTRING, UINT32, RANDUINT32, RANDALPHANUMSTRING, RANDNUMSTRING, RANDALPHASTRING, RANDHEXSTRING])

=s basicmod

appends an AVP to each Diameter message

=d

Appends one AVP to the end of every Diameter message and updates the message
Length field. The AVP carries the AVP Code CODE and an M bit from MANDATORY;
the V bit and the vendor id come from VENDORSPEC and VENDOR. The AVP is
padded to a 4-octet boundary with zero octets, and its own Length counts the
header and the value but not that padding, per RFC 6733 section 4.1. The header
is 8 octets, or 12 when VENDORSPEC is true.

A vendor AVP must carry a non-zero Vendor-Id: VENDORSPEC true with VENDOR absent
or zero fails configuration, because RFC 6733 section 4.1.1 forbids the value
zero when the V bit is set.

The message is validated before the append, so a malformed packet is dropped
rather than rewritten: the element prints one
C<DiameterPushAVP: dropping malformed packet: REASON> line when the Version
field is not 1, when the packet is shorter than the 20-octet header, when its
Length field is not a multiple of 4, when its Length field does not equal the
packet length, when the flags are illegal for the message type, or when an AVP
in it is malformed or runs past the message end.

An append that would push the message Length past three octets is dropped too,
with its own line: C<DiameterPushAVP: dropping packet: appending the AVP would
exceed the three-octet Length field (RFC 6733 section 3)>, and nothing is
forwarded. That decision is made per packet, because the value decides the
final length; the message itself is well formed, so the line does not report
malformed input. A message whose appended total stays at or below 0xFFFFFF is
appended as usual. A RAND*STRING count is capped at 16,777,184 (16,777,180 with
the vendor header): a longer value cannot fit the three-octet message Length
even in a 20-octet message, so it fails configuration instead of being
materialised and dropped on every packet.

At most one value source may supply the value: a configuration that supplies
two of OCTETSTRING, UINT32, RANDUINT32, RANDALPHANUMSTRING, RANDNUMSTRING,
RANDALPHASTRING and RANDHEXSTRING fails configuration with an error naming the
first conflicting pair in that documented argument order, because resolving the
pair by precedence would silently discard the argument that decides the encoded
value type. A repeated keyword fails configuration too, with an error naming it
(C<the OCTETSTRING argument is given more than once>), because Click's parser
would otherwise keep the last occurrence and silently discard the earlier value.
Each source counts as
supplied on its own terms: OCTETSTRING and UINT32 when the keyword is present --
an empty string and a zero number are values, not absences -- RANDUINT32 only
when true, and a RAND*STRING generator only when its count is above zero, the
documented "unused" value. Supplying no source at all is the empty-value case
below, and a configuration that relied on the old precedence must keep only the
source it wants.

The value is a string when the source supplies one: the OCTETSTRING octets, or
the generator's characters from its alphabet. Otherwise it is a 4-octet
big-endian number -- the RANDUINT32 draw or the UINT32 value. A zero number is
still a 4-octet value, so the AVP Length is 12 (16 with the vendor header), as
RFC 6733 section 4.2 requires for Unsigned32.

An AVP with no value is 8 octets long (12 with the vendor header), which is the
empty-OctetString case section 4.2 permits: an empty OCTETSTRING, or no string
source and no numeric source at all. This element has no dictionary, so it
cannot tell an OctetString AVP from an Unsigned32 one; an AVP whose application
specification makes it Unsigned32 or Integer32 needs UINT32 or RANDUINT32,
because a value-less one does not have the length section 4.2 requires.

Keyword arguments are:

=over 8

=item CODE

Integer. Required. The AVP Code.

=item VENDORSPEC

Boolean. If true the AVP gets the 12-octet vendor header with the V bit set.
Default is false.

=item VENDOR

Integer. Required when VENDORSPEC is true and must be non-zero: the Vendor-Id
written into the vendor header. When VENDORSPEC is false the vendor id is 0 and
VENDOR is ignored.

=item MANDATORY

Boolean. If true the AVP's M bit is set, telling a receiving peer that support
for this AVP is required (RFC 6733 section 4.1). M is 0x40 in the flags octet
and is independent of the V bit (0x80), and setting it changes neither the AVP
nor the message Length. Default is false.

=item OCTETSTRING

String. The value as literal octets. Cannot be combined with UINT32,
RANDUINT32 or a RAND*STRING generator: supplying a second value source fails
configuration. An empty string appends an AVP with no value: Length 8, or 12
with the vendor header.

=item UINT32

Integer. The value as a 4-octet big-endian number. Cannot be combined with
OCTETSTRING, RANDUINT32 or a RAND*STRING generator: supplying a second value
source fails configuration. A value of 0 is four zero octets, so the AVP Length
is 12 (16 with the vendor header), per RFC 6733 section 4.2.

=item RANDUINT32

Boolean. If true, a random 4-octet number drawn from click_random() is the
value. Cannot be combined with OCTETSTRING, UINT32 or a RAND*STRING generator:
supplying a second value source fails configuration. Every draw is four octets,
including a draw of zero: the AVP Length is 12 (16 with the vendor header), per
RFC 6733 section 4.2. Default is false, which supplies nothing.

=item RANDALPHANUMSTRING

Integer. Generates that many characters from C<0>-C<9>, C<A>-C<Z> and
C<a>-C<z>. Cannot be combined with any other value source: supplying a second
one fails configuration. Zero means unused, which is the default. At most
16,777,184 (16,777,180 with the vendor header); a larger count fails
configuration because the AVP cannot fit the three-octet message Length.

=item RANDNUMSTRING

Integer. Generates that many characters from C<0>-C<9>. Cannot be combined with
any other value source: supplying a second one fails configuration. Zero means
unused, which is the default. At most 16,777,184 (16,777,180 with the vendor
header); a larger count fails configuration.

=item RANDALPHASTRING

Integer. Generates that many characters from C<A>-C<Z> and C<a>-C<z>. Cannot be
combined with any other value source: supplying a second one fails
configuration. Zero means unused, which is the default. At most 16,777,184
(16,777,180 with the vendor header); a larger count fails configuration.

=item RANDHEXSTRING

Integer. Generates that many characters from C<0>-C<9> and C<A>-C<F>. Cannot be
combined with any other value source: supplying a second one fails
configuration. Zero means unused, which is the default. At most 16,777,184
(16,777,180 with the vendor header); a larger count fails configuration.

=back

=a

DiameterPopAVP, DiameterPopStorePushAVP, DiameterAvpEncap
*/

class DiameterPushAVP : public Element
{
public:
	DiameterPushAVP() CLICK_COLD;
	const char *class_name() const		{ return "DiameterPushAVP"; }
	const char *port_count() const		{ return PORTS_1_1; }

	int configure(Vector<String> &conf, ErrorHandler *errh) CLICK_COLD;
	Packet *simple_action(Packet *);

private:
	// Configuration only: configure() fills these, and simple_action() reads
	// them into per-packet locals instead of writing them.
	AvpHeader ah;
	String datastring;
	uint32_t datauint;
	// Whether a numeric source was supplied (UINT32 present, or RANDUINT32
	// true). Presence, not magnitude: a supplied or drawn zero is four octets.
	bool hasUint;
	bool randUInt32;
	size_t randAlphaNumString;
	size_t randNumString;
	size_t randAlphaString;
	size_t randHexString;
};

CLICK_ENDDECLS
#endif /* DIAMETERPUSHAVP_HH_ */
