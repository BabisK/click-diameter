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
C<DiameterPushAVP: dropping malformed packet: REASON> line when the packet is
shorter than the 20-octet header, when its Length field does not equal the
packet length, when an AVP in it is malformed or runs past the message end, or
when the flags are illegal for the message type.

The value is a string when a source supplies one. With RANDUINT32 unset, the
first of RANDALPHANUMSTRING, RANDNUMSTRING, RANDALPHASTRING and RANDHEXSTRING
whose count is above zero generates it; otherwise a non-empty OCTETSTRING is
used. A non-empty OCTETSTRING wins even over RANDUINT32, because the string is
never cleared. When no string is available the value is a 4-octet big-endian
number -- the RANDUINT32 draw when RANDUINT32 is set, UINT32 otherwise -- and a
zero number leaves the AVP without a value. An AVP with no value is 8 octets
long (12 with the vendor header).

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

String. The value as literal octets, used when no RAND*STRING generator
supplies one.

=item UINT32

Integer. The value as a 4-octet big-endian number. Used only when no string is
available and RANDUINT32 is false; a value of 0 leaves the AVP without a
value.

=item RANDUINT32

Boolean. If true, a random 4-octet number drawn from click_random() is the
value when no string is set, and the string generators do not run. Default is
false.

=item RANDALPHANUMSTRING

Integer. Generates that many characters from C<0>-C<9>, C<A>-C<Z> and
C<a>-C<z>. Zero means unused, which is the default.

=item RANDNUMSTRING

Integer. Generates that many characters from C<0>-C<9>. Zero means unused,
which is the default.

=item RANDALPHASTRING

Integer. Generates that many characters from C<A>-C<Z> and C<a>-C<z>. Zero
means unused, which is the default.

=item RANDHEXSTRING

Integer. Generates that many characters from C<0>-C<9> and C<A>-C<F>. Zero
means unused, which is the default.

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
	bool randUInt32;
	size_t randAlphaNumString;
	size_t randNumString;
	size_t randAlphaString;
	size_t randHexString;
};

CLICK_ENDDECLS
#endif /* DIAMETERPUSHAVP_HH_ */
