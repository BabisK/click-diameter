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

	// The padding is whatever takes the declared AVP length to the next
	// 4-octet boundary. It is derived from Length alone -- never from the
	// padding octets, which RFC 6733 section 4 requires to be zero.
	const uint32_t paddedLength = (avpLength + 3) & ~3u;

	if (p_in->length() > paddedLength)
	{
		// Octets follow this AVP: drop it whole, padding included, so the
		// next AVP starts at offset 0 and the walk stays aligned.
		p_in->pull(paddedLength);
	}
	else
	{
		// This AVP is the whole packet: drop its padding, if any, then its
		// header, and forward the value. A legacy unpadded AVP decodes the
		// same way because there is no padding to drop.
		if (p_in->length() > avpLength)
			p_in->take(p_in->length() - avpLength);
		p_in->pull(headerLength);
	}

	return p_in;
}

CLICK_ENDDECLS
EXPORT_ELEMENT(DiameterAvpDecap)
