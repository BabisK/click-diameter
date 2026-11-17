/*
 * diameterdecap.{cc,hh} -- element that removes a Diameter header from the packet
 * Charalampos "Babis" Kaidos
 */

#ifndef DIAMETERDECAP_HH_
#define DIAMETERDECAP_HH_
#include <click/element.hh>
#include "diameter.hh"
CLICK_DECLS

/*
=c

DiameterDecap()

=s basictransfer

strips the Diameter header from each packet

=d

Checks the whole Diameter message at the front of the packet and, when it is
well formed, removes the 20-octet header and forwards the rest of the packet
unchanged. The body is part of the message, so it is walked: the message must be
a sequence of AVPs that each pass the package's AVP checks. (DiameterAvpDecap
reads one AVP on its own; this element reads a message.)

A packet is dropped rather than forwarded when any of these holds, and the
element prints one C<DiameterDecap: dropping malformed packet: REASON> line
naming the reason:

=over 8

=item *

the Version field is not 1;

=item *

the packet is shorter than the 20-octet header;

=item *

its Length field is not a multiple of 4;

=item *

the header's Length field does not equal the packet length;

=item *

the E bit is set on a request;

=item *

the T bit is set on an answer;

=item *

an AVP in the body is malformed, runs past the message end, or carries the V
bit with a zero Vendor-Id.

=back

P on either type and T on a request are not errors. The element takes no
arguments.

=a

DiameterEncap, DiameterPopAVP
*/

class DiameterDecap : public Element
{
public:
	DiameterDecap() CLICK_COLD;

	const char *class_name() const		{ return "DiameterDecap"; }
    const char *port_count() const		{ return PORTS_1_1; }

    Packet *simple_action(Packet * p_in);
};

CLICK_ENDDECLS
#endif /* DIAMETERDECAP_HH_ */
