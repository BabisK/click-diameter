/*
 * diameteravpdecap.{cc,hh} -- element that removes a Diameter AVP header from the packet
 * Charalampos "Babis" Kaidos
 */

#ifndef DIAMETERAVPDECAP_HH
#define DIAMETERAVPDECAP_HH
#include <click/element.hh>
#include "diameter.hh"
CLICK_DECLS

/*
=c

DiameterAvpDecap()

=s basictransfer

strips one AVP header and its padding from each packet

=d

Consumes one AVP from the front of the packet. The V bit decides whether the
header is 8 or 12 octets, and the padding is derived from the AVP Length alone,
rounding up to the next 4-octet boundary.

When octets follow the AVP in the packet, the element pulls the whole padded AVP
-- header, value and padding -- so the next AVP starts at offset 0 and a walk
stays aligned. When the AVP is the whole packet, it strips the padding and then
the header and forwards the value; a standalone AVP that arrives without its
padding decodes the same way, because there is nothing to strip.

A packet is dropped rather than forwarded when the AVP cannot be read, and the
element prints one C<DiameterAvpDecap: dropping malformed packet: REASON> line:

=over 8

=item *

the packet is shorter than the 8-octet AVP header;

=item *

the packet is shorter than the 12-octet vendor header that its V bit
announces;

=item *

the AVP Length is below its own header;

=item *

the AVP Length runs past the end of the packet.

=back

The element takes no arguments.

=a

DiameterAvpEncap, DiameterPopAVP
*/

class DiameterAvpDecap : public Element
{
public:
	DiameterAvpDecap() CLICK_COLD;

	const char *class_name() const		{ return "DiameterAvpDecap"; }
    const char *port_count() const		{ return PORTS_1_1; }

    Packet *simple_action(Packet * p_in);
};

CLICK_ENDDECLS
#endif /* DIAMETERAVPDECAP_HH */
