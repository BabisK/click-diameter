/*
 * diameterpopstorepushavp.{cc,hh} -- element that removes the last avp from the packet
 * and stores it. When the packet passes from the second port the avp is pushed on it
 * Charalampos "Babis" Kaidos
 */

#include <click/config.h>
#include "diameterpopstorepushavp.hh"
#include <click/args.hh>
#include <click/confparse.hh>
#include <click/glue.hh>
CLICK_DECLS

DiameterPopStorePushAVP::DiameterPopStorePushAVP()
: data(NULL) {}

DiameterPopStorePushAVP::~DiameterPopStorePushAVP()
{
	if(data != NULL)
	{
		delete[] data;
	}
}

void DiameterPopStorePushAVP::push(int, Packet* p)
{
	if(data == NULL)
	{
		if ((p = process(p)))
		{
			output(0).push(p);
		}
	}
	else
	{
		if ((p = process(p)))
		{
			output(1).push(p);
		}
	}
}

Packet* DiameterPopStorePushAVP::process(Packet * p_in)
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

	DiameterHeader dh;
	dh.decode(p_in->data());
	const uint32_t messageLength = dh.getLength();
	WritablePacket* wp;

	if(data == NULL)
	{
		// A message with no AVPs stores nothing; forward it unchanged.
		if (!lastAvpOffset)
		{
			return p_in;
		}
		const uint8_t* lastAvp = p_in->data() + lastAvpOffset;
		ah.decode(lastAvp);
		uint32_t headerLength = ah.getHeaderLength();
		data = new uint8_t[ah.getLength() - headerLength];
		memcpy(data, lastAvp + headerLength, ah.getLength() - headerLength);
		dh.setLength(messageLength - ah.getLengthPadded());
		p_in->take(ah.getLengthPadded());
		// The packet may be freed when the copy cannot be allocated; the AVP
		// just popped stays in the store for the next packet.
		wp = p_in->put(0);
		if (!wp)
			return 0;
		dh.encode(wp->data());
	}
	else
	{
		// RFC 6733 section 3 fixes the Message Length at three octets. Keep the
		// stored AVP when the packet cannot carry it, so a later packet can; the
		// drop is reported here rather than discovered as a wrapped Length.
		if (ah.getLengthPadded() > DIAMETER_MAX_24BIT_VALUE - messageLength)
		{
			click_chatter("%s: dropping packet: pushing the stored AVP would exceed the three-octet Length field (RFC 6733 section 3)", class_name());
			p_in->kill();
			return 0;
		}
		wp = p_in->put(ah.getLengthPadded());
		if (!wp)
			return 0;
		memset(wp->data() + messageLength, 0, ah.getLengthPadded());
		ah.encode(wp->data() + messageLength);
		uint32_t headerLength = ah.getHeaderLength();
		memcpy(wp->data() + messageLength + headerLength, data, ah.getLength() - headerLength);
		dh.setLength(messageLength + ah.getLengthPadded());
		dh.encode(wp->data());
		delete[] data;
		data = NULL;
	}
	return wp;
}

CLICK_ENDDECLS
EXPORT_ELEMENT(DiameterPopStorePushAVP)
