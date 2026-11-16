/*
 * diameterfliprequest.{cc,hh} -- element that changes the request flag of the diameter message
 * Charalampos "Babis" Kaidos
 */

#include <click/config.h>
#include "diameterfliprequest.hh"
#include <click/args.hh>
#include <click/glue.hh>
CLICK_DECLS

DiameterFlipRequest::DiameterFlipRequest(){}

Packet* DiameterFlipRequest::simple_action(Packet * p_in)
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

	WritablePacket * wp = p_in->put(0);
	DiameterHeader dh;
	dh.decode(wp->data());
	if (dh.isRequest())
	{
		// This package keeps P off the answers it produces (CAP-5): RFC 6733
		// section 3 forbids E in requests and T in answers, while section 6.2
		// makes an answer's P mirror the request's, so the rule enforced here
		// is the package's own.
		dh.setRequest(false);
		dh.setProxiable(false);
	}
	else
	{
		dh.setRequest(true);
	}
	dh.encode(wp->data());
	return wp;
}

CLICK_ENDDECLS
EXPORT_ELEMENT(DiameterFlipRequest)
