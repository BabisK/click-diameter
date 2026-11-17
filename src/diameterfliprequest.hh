/*
 * diameterfliprequest.{cc,hh} -- element that changes the request flag of the diameter message
 * Charalampos "Babis" Kaidos
 */

#ifndef DIAMETERFLIPREQUEST_HH_
#define DIAMETERFLIPREQUEST_HH_
#include <click/element.hh>
#include "diameter.hh"
CLICK_DECLS

/*
=c

DiameterFlipRequest()

=s basicmod

turns a Diameter request into an answer and back

=d

Flips the message type: a request becomes an answer and an answer becomes a
request. The P bit is kept in both directions, because RFC 6733 section 6.2
sets an answer's P to the same value as the request's.

A request carries no E and an answer carries no T, so the element clears T when
it produces an answer and clears E when it produces a request, keeping the
result legal per section 3. Of the fields the header models, nothing else
changes: the Length, the identifiers and every AVP stay as they were.
Re-encoding writes only the modelled flags, so the reserved flag bits of an
accepted nonconforming frame come back zero.

The header is validated before the flip, so a malformed packet is dropped
rather than repaired: the element prints one
C<DiameterFlipRequest: dropping malformed packet: REASON> line when the Version
field is not 1, when the packet is shorter than the 20-octet header, when its
Length field is not a multiple of 4, when its Length field does not equal the
packet length, when the E bit is set on a request, or when the T bit is set on
an answer. P on either type and T on a request are not errors. The element
takes no arguments.

=a

DiameterEncap, DiameterRatedSource
*/

class DiameterFlipRequest : public Element
{
public:
	DiameterFlipRequest() CLICK_COLD;

	const char *class_name() const		{ return "DiameterFlipRequest"; }
	const char *port_count() const		{ return PORTS_1_1; }

	Packet *simple_action(Packet * p_in);
};

CLICK_ENDDECLS
#endif /* DIAMETERFLIPREQUEST_HH_ */
