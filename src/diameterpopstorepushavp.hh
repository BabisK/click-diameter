/*
 * diameterpopstorepushavp.{cc,hh} -- element that removes the last avp from the packet
 * and stores it. When the packet passes from the second port the avp is pushed on it
 * Charalampos "Babis" Kaidos
 */

#ifndef DIAMETERPOPSTOREPUSHAVP_HH_
#define DIAMETERPOPSTOREPUSHAVP_HH_
#include <click/element.hh>
#include "diameter.hh"
CLICK_DECLS

/*
=c

DiameterPopStorePushAVP()

=s basicmod

moves the last AVP of one message onto a later one

=d

Pops the last AVP of one message and pushes it back onto a later one. The
element has one input and two outputs and works in a push context only.

On the first packet, while no AVP is stored, the element validates the message,
records the final AVP's header, copies its value, removes the AVP from the
message together with its zero pad octets, subtracts its padded length from the
message Length, and sends the shortened message to output 0. On a later packet,
while an AVP is stored, it validates the message, appends the stored AVP
unchanged, adds its padded length to the message Length, sends the message to
output 1 and clears the store.

A first packet that carries no AVPs is forwarded to output 0 unchanged and
stores nothing, so the next packet is treated as another first packet.

A malformed packet is dropped rather than rewritten: the element prints one
C<DiameterPopStorePushAVP: dropping malformed packet: REASON> line when the
Version field is not 1, when the packet is shorter than the 20-octet header,
when its Length field is not a multiple of 4, when its Length field does not
equal the packet length, when the flags are illegal for the message type, or
when an AVP in it is malformed or runs past the message end. A drop sends
nothing to either output and leaves the store as it was. The Message Length is
three octets, so when the stored AVP would push a message past 0xFFFFFF the
packet is dropped with C<DiameterPopStorePushAVP: dropping packet: pushing the
stored AVP would exceed the three-octet Length field (RFC 6733 section 3)>, and
the stored AVP is kept so a later packet can carry it. The element takes no
arguments.

=a

DiameterPopAVP, DiameterPushAVP
*/

class DiameterPopStorePushAVP : public Element
{
public:
	DiameterPopStorePushAVP() CLICK_COLD;
	~DiameterPopStorePushAVP() CLICK_COLD;

	const char *class_name() const		{ return "DiameterPopStorePushAVP"; }
	const char *port_count() const		{ return "1/2"; }

	void push(int, Packet* p);
private:
	Packet *process(Packet *);
	AvpHeader ah;
	uint8_t* data;
};

CLICK_ENDDECLS
#endif /* DIAMETERPOPSTOREPUSHAVP_HH_ */
