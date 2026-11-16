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
		// RFC 6733 section 3 forbids T in an answer. The answer keeps the
		// request's P, because section 6.2 sets an answer's P "to the same value
		// as the one in the request".
		dh.setRequest(false);
		dh.setRetransmitted(false);
	}
	else
	{
		// RFC 6733 section 3 forbids E in a request; P is mirrored the same way
		// in this direction, so a proxiable answer yields a proxiable request.
		dh.setRequest(true);
		dh.setError(false);
	}
	dh.encode(wp->data());
	return wp;
}

CLICK_ENDDECLS
EXPORT_ELEMENT(DiameterFlipRequest)
