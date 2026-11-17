/*
 * diameterpopavp.{cc,hh} -- element that removes the last avp from the packet
 * Charalampos "Babis" Kaidos
 */

#ifndef DIAMETERPOPAVP_HH_
#define DIAMETERPOPAVP_HH_
#include <click/element.hh>
#include "diameter.hh"
CLICK_DECLS

/*
=c

DiameterPopAVP()

=s basicmod

removes the last AVP from each Diameter message

=d

Removes the final AVP from a well-formed Diameter message, including its zero
pad octets, and subtracts the AVP's padded length from the message Length
field. A message that carries no AVPs has nothing to pop and is forwarded
unchanged, header and all; nothing else about the message is rewritten.

The message is validated before the AVP is removed, so a malformed packet is
dropped rather than rewritten: the element prints one
C<DiameterPopAVP: dropping malformed packet: REASON> line when the Version field
is not 1, when the packet is shorter than the 20-octet header, when its Length
field is not a multiple of 4, when its Length field does not equal the packet
length, when the flags are illegal for the message type, or when an AVP in it is
malformed or runs past the message end. The element takes no arguments.

=a

DiameterPushAVP, DiameterPopStorePushAVP, DiameterAvpDecap
*/

class DiameterPopAVP : public Element
{
public:
	DiameterPopAVP() CLICK_COLD;
	const char *class_name() const		{ return "DiameterPopAVP"; }
	const char *port_count() const		{ return PORTS_1_1; }

	Packet *simple_action(Packet *);
};

CLICK_ENDDECLS
#endif /* DIAMETERPOPAVP_HH_ */
