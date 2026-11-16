/*
 * diameterencap.{cc,hh} -- element that puts a Diameter header on the packet
 * Charalampos "Babis" Kaidos
 */

#include <click/config.h>
#include "diameterencap.hh"
#include <click/args.hh>
#include <click/error.hh>
#include <click/glue.hh>
CLICK_DECLS

DiameterEncap::DiameterEncap(){}

int DiameterEncap::configure(Vector<String> &conf, ErrorHandler *errh)
{
	uint32_t code;
	bool request;
	bool error = false;
	bool proxiable = false;
	bool retransmited = false;
	uint32_t appid = 0;

	if (Args(conf, this, errh)
	.read_m("CODE", code)
	.read_m("REQUEST", request)
	.read("ERROR", error)
	.read("PROXIABLE", proxiable)
	.read("RETRANSMITED", retransmited)
	.read("APPID", appid)
	.complete() < 0)
	return -1;

	// RFC 6733 section 3 forbids E in a request and T in an answer, so reject
	// either pair rather than discard an argument the caller wrote. P is legal
	// on both: section 6.2 makes an answer mirror the request it answers, and
	// this element has no request to consult, so the caller's declaration
	// stands.
	if (request && error)
		return errh->error("the ERROR argument cannot be set on a request (RFC 6733 section 3)");
	if (!request && retransmited)
		return errh->error("the RETRANSMITED argument cannot be set on an answer (RFC 6733 section 3)");

	dh.setCode(code);
	dh.setRequest(request);
	dh.setError(error);
	dh.setProxiable(proxiable);
	dh.setRetransmitted(retransmited);
	dh.setAppId(appid);

	return 0;
}

Packet* DiameterEncap::simple_action(Packet * p_in)
{
	dh.setHbh(click_random());
	dh.setE2e(click_random());
	dh.setLength(DIAMETER_MESSAGE_HEADER_LENGTH + p_in->length());

	WritablePacket* wp = p_in->push(DIAMETER_MESSAGE_HEADER_LENGTH);
	dh.encode(wp->data());

	return wp;
}

CLICK_ENDDECLS
EXPORT_ELEMENT(DiameterEncap)
