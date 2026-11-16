/*
 * diameteravpdecap.{cc,hh} -- element that removes a Diameter AVP header from the packet
 * Charalampos "Babis" Kaidos
 */

#include <click/config.h>
#include "diameteravpdecap.hh"
#include <click/args.hh>
#include <click/glue.hh>
CLICK_DECLS

DiameterAvpDecap::DiameterAvpDecap(){}

Packet* DiameterAvpDecap::simple_action(Packet * p_in)
{
	uint32_t headerLength;
	uint32_t avpLength;
	DiameterCheck check = diameter_check_avp(p_in->data(), p_in->length(),
			&headerLength, &avpLength);
	if (check != DIAMETER_CHECK_OK)
	{
		click_chatter("%s: dropping malformed packet: %s", class_name(),
				diameter_check_reason(check));
		p_in->kill();
		return 0;
	}
	p_in->pull(headerLength);

	return p_in;
}

CLICK_ENDDECLS
EXPORT_ELEMENT(DiameterAvpDecap)
