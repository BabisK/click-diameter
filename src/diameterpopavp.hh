/*
 * diameterpopavp.{cc,hh} -- element that removes the last avp from the packet
 * Charalampos "Babis" Kaidos
 */

#ifndef DIAMETERPOPAVP_HH_
#define DIAMETERPOPAVP_HH_
#include <click/element.hh>
#include "diameter.hh"
CLICK_DECLS

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
