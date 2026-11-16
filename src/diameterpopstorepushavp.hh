/*
 * diameterpopstorepushavp.{cc,hh} -- element that removes the last avp from the packet
 * and stores it. When the packet passes from the second port the avp is pushed on it
 * Charalampos "Babis" Kaidos
 */

#ifndef DIAMETERPOPSTOREUSHAVP_HH_
#define DIAMETERPOPSTOREUSHAVP_HH_
#include <click/element.hh>
#include "diameter.hh"
CLICK_DECLS

class DiameterPopStorePushAVP : public Element
{
public:
	DiameterPopStorePushAVP() CLICK_COLD;
	~DiameterPopStorePushAVP() CLICK_COLD;

	const char *class_name() const		{ return "DiameterPopStorePushAVP"; }
	const char *port_count() const		{ return "1/2"; }

	void push(int, Packet* p);
	Packet *simple_action(Packet *);
private:
	AvpHeader ah;
	uint8_t* data;
};

CLICK_ENDDECLS
#endif /* DIAMETERPOPSTOREUSHAVP_HH_ */
