/*
 * diameterpopavp.{cc,hh} -- element that removes the last avp from the packet
 * Charalampos "Babis" Kaidos
 */

#include <click/config.h>
#include "diameterpopavp.hh"
#include <click/args.hh>
#include <click/confparse.hh>
#include <click/glue.hh>
#include <iostream>
CLICK_DECLS

DiameterPopAVP::DiameterPopAVP(){}

Packet* DiameterPopAVP::simple_action(Packet * p_in)
{
	uint32_t lastAvpOffset;
	DiameterCheck check = diameter_check_message(p_in->data(), p_in->length(),
			&lastAvpOffset);
	if (check != DIAMETER_CHECK_OK)
	{
		click_chatter("%s: dropping malformed packet: %s", class_name(),
				diameter_check_reason(check));
		p_in->kill();
		return 0;
	}

	// A message with no AVPs has nothing to pop; forwarding it is a no-op.
	if (!lastAvpOffset)
	{
		return p_in;
	}

	DiameterHeader dh;
	dh.decode(p_in->data());
	const uint32_t messageLength = dh.getLength();

	AvpHeader ah;
	ah.decode(p_in->data() + lastAvpOffset);
	p_in->take(ah.getLengthPadded());
	WritablePacket* wp = p_in->put(0);
	dh.setLength(messageLength - ah.getLengthPadded());
	dh.encode(wp->data());

	return wp;
}

CLICK_ENDDECLS
EXPORT_ELEMENT(DiameterPopAVP)
