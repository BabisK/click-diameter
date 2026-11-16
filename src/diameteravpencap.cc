/*
 * diameteravpencap.{cc,hh} -- element that puts a Diameter AVP header on the packet
 * Charalampos "Babis" Kaidos
 */

#include <click/config.h>
#include "diameteravpencap.hh"
#include <click/args.hh>
#include <click/glue.hh>
CLICK_DECLS

DiameterAvpEncap::DiameterAvpEncap(){}

int DiameterAvpEncap::configure(Vector<String> &conf, ErrorHandler *errh)
{
	uint32_t code;
	uint32_t vendorId = 0;
	bool mandatory = false;

	if (Args(conf, this, errh)
	.read_m("CODE", code)
	.read("VENDORID", vendorId)
	.read("MANDATORY", mandatory)
	.complete() < 0)
	return -1;

	ah.setCode(code);
	ah.setMandatory(mandatory);
	if(vendorId != 0)
	{
		ah.setVendorSpecific(true);
		ah.setVendorId(vendorId);
	}
	else
	{
		ah.setVendorSpecific(false);
		ah.setVendorId(0);
	}

	return 0;
}

Packet* DiameterAvpEncap::simple_action(Packet * p_in)
{
	// RFC 6733 section 4.1: the AVP Length counts the header and the value but
	// not the zero octets that pad the AVP up to a 4-octet boundary.
	const uint32_t valueLength = p_in->length();
	ah.setLength(ah.getHeaderLength() + valueLength);
	const uint32_t paddingLength = ah.getLengthPadded() - ah.getLength();

	WritablePacket* wp = p_in->push(ah.getHeaderLength());
	if (paddingLength > 0)
	{
		wp = wp->put(paddingLength);
		memset(wp->data() + ah.getHeaderLength() + valueLength, 0,
				paddingLength);
	}
	ah.encode(wp->data());

	return wp;
}

CLICK_ENDDECLS
EXPORT_ELEMENT(DiameterAvpEncap)
