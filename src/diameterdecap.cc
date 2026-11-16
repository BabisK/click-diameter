/*
 * diameterdecap.{cc,hh} -- element that removes a Diameter header from the packet
 * Charalampos "Babis" Kaidos
 */

#include <click/config.h>
#include "diameterdecap.hh"
#include <click/args.hh>
#include <click/glue.hh>
CLICK_DECLS

DiameterDecap::DiameterDecap(){}

Packet* DiameterDecap::simple_action(Packet * p_in)
{
	const DiameterCheck check = diameter_check_header(p_in->data(),
			p_in->length());
	if (check != DIAMETER_CHECK_OK)
	{
		click_chatter("%s: dropping malformed packet: %s", class_name(),
				diameter_check_reason(check));
		p_in->kill();
		return 0;
	}
	p_in->pull(DIAMETER_MESSAGE_HEADER_LENGTH);
	return p_in;
}

CLICK_ENDDECLS
EXPORT_ELEMENT(DiameterDecap)
