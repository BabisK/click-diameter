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
	// The whole message is validated, not just the header: a body that is not
	// a sequence of well-formed AVPs is malformed too, and forwarding it would
	// hand the next element (or a peer) a frame that still carries the defect.
	// The shared walk also rejects an AVP with V set and a zero Vendor-Id
	// (RFC 6733 section 4.1.1).
	const DiameterCheck check = diameter_check_message(p_in->data(),
			p_in->length(), 0);
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
