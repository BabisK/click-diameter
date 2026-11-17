/*
 * diameteravpencap.{cc,hh} -- element that puts a Diameter AVP header on the packet
 * Charalampos "Babis" Kaidos
 */

#include <click/config.h>
#include "diameteravpencap.hh"
#include "diameterconf.hh"
#include <click/args.hh>
#include <click/glue.hh>
CLICK_DECLS

DiameterAvpEncap::DiameterAvpEncap(){}

int DiameterAvpEncap::configure(Vector<String> &conf, ErrorHandler *errh)
{
	uint32_t code;
	uint32_t vendorId = 0;
	bool mandatory = false;

	static const char *const keywords[] = { "CODE", "VENDORID", "MANDATORY" };
	if (diameter_reject_duplicate_keywords(conf, errh, keywords,
			sizeof(keywords) / sizeof(keywords[0])) < 0)
		return -1;

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
	// Click does not serialise a push element across router threads, so the
	// configured header is copied per packet: the Length and the header it is
	// encoded into always belong to the same packet.
	AvpHeader header = ah;

	// RFC 6733 section 4.1: the AVP Length counts the header and the value but
	// not the zero octets that pad the AVP up to a 4-octet boundary.
	const uint32_t valueLength = p_in->length();
	const uint32_t headerLength = header.getHeaderLength();
	// RFC 6733 section 4.1 fixes the AVP Length at three octets. A value that
	// cannot fit is dropped with its own warning instead of being wrapped into
	// a length the envelope does not have. The guard runs before push(), so the
	// drop prints no Put advisory.
	if (valueLength > DIAMETER_MAX_24BIT_VALUE - headerLength)
	{
		click_chatter("%s: dropping packet: the AVP Length would exceed the three-octet field (RFC 6733 section 4.1)", class_name());
		p_in->kill();
		return 0;
	}
	header.setLength(headerLength + valueLength);
	const uint32_t paddingLength = header.getLengthPadded() - header.getLength();

	// As in DiameterEncap: a failed extension returns null and frees the
	// packet, so the packet is dropped instead of dereferenced.
	WritablePacket* wp = p_in->push(headerLength);
	if (!wp)
		return 0;
	if (paddingLength > 0)
	{
		wp = wp->put(paddingLength);
		if (!wp)
			return 0;
		memset(wp->data() + headerLength + valueLength, 0, paddingLength);
	}
	header.encode(wp->data());

	return wp;
}

CLICK_ENDDECLS
EXPORT_ELEMENT(DiameterAvpEncap)
