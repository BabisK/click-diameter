/*
 * diameteravpencap.{cc,hh} -- element that puts a Diameter AVP header on the packet
 * Charalampos "Babis" Kaidos
 */

#ifndef DIAMETERAVPENCAP_HH_
#define DIAMETERAVPENCAP_HH_
#include <click/element.hh>
#include "diameter.hh"
CLICK_DECLS

/*
=c

DiameterAvpEncap(CODE [, VENDORID, MANDATORY])

=s basictransfer

prepends an AVP header to each packet

=d

Treats the whole incoming packet as an AVP value and prepends an AVP header to
it. The header carries the AVP Code CODE, the M bit from MANDATORY, and a Length
of the header size plus the value length. VENDORID selects the header size: zero
gives the plain 8-octet header with the V bit clear, and a non-zero value gives
the 12-octet vendor header with V set and that Vendor-Id.

The AVP is padded to a 4-octet boundary with zero octets and its Length excludes
that padding, per RFC 6733 section 4.1, so a sequence of encoder outputs stays
aligned. The AVP Length is three octets, so a value that cannot fit is dropped
with C<DiameterAvpEncap: dropping packet: the AVP Length would exceed the
three-octet field (RFC 6733 section 4.1)> rather than emitted with a wrapped
field. The payload is not validated or interpreted; this element is a writer,
not a reader. A keyword repeated in one configuration fails configuration too,
with C<the CODE argument is given more than once>, rather than silently keeping
the last value.

Keyword arguments are:

=over 8

=item CODE

Integer. Required. The AVP Code.

=item VENDORID

Integer. Vendor-Id written into the vendor header; a non-zero value also turns
the V bit on and widens the header to 12 octets. Default is 0, which selects
the 8-octet header.

=item MANDATORY

Boolean. Sets the M bit. Default is false.

=back

=a

DiameterAvpDecap, DiameterPushAVP
*/

class DiameterAvpEncap : public Element
{
public:
	DiameterAvpEncap() CLICK_COLD;

	const char *class_name() const		{ return "DiameterAvpEncap"; }
    const char *port_count() const		{ return PORTS_1_1; }

    int configure(Vector<String> &conf, ErrorHandler *errh) CLICK_COLD;
    Packet *simple_action(Packet * p_in);

private:
    // Configuration only: configure() fills it, and simple_action() copies it
    // into a local header per packet instead of writing it.
    AvpHeader ah;
};

CLICK_ENDDECLS
#endif /* DIAMETERAVPENCAP_HH_ */
