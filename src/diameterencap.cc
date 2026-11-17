/*
 * diameterencap.{cc,hh} -- element that puts a Diameter header on the packet
 * Charalampos "Babis" Kaidos
 */

#include <click/config.h>
#include "diameterencap.hh"
#include "diameterconf.hh"
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

	static const char *const keywords[] = {
		"CODE", "REQUEST", "ERROR", "PROXIABLE", "RETRANSMITED", "APPID"
	};
	if (diameter_reject_duplicate_keywords(conf, errh, keywords,
			sizeof(keywords) / sizeof(keywords[0])) < 0)
		return -1;

	if (Args(conf, this, errh)
	.read_m("CODE", code)
	.read_m("REQUEST", request)
	.read("ERROR", error)
	.read("PROXIABLE", proxiable)
	.read("RETRANSMITED", retransmited)
	.read("APPID", appid)
	.complete() < 0)
	return -1;

	// RFC 6733 section 3 fixes the Command Code at three octets, so a larger
	// value cannot be encoded: the low three octets of 0x01000118 are 0x000118,
	// and storing it would silently emit a different message type. A value that
	// cannot be written is a caller error, so refuse the configuration rather
	// than truncate it. 0xFFFFFE and 0xFFFFFF are section 3.1's experimental
	// values and stay in range.
	if (code > DIAMETER_MAX_24BIT_VALUE)
		return errh->error("the CODE argument must not exceed 0xFFFFFF: the Command Code field is three octets (RFC 6733 section 3)");

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

int DiameterEncap::initialize(ErrorHandler *)
{
	// Seed once, after every element has been configured, so RandomSeed has
	// already applied its seed wherever its statement sits. Name the two draws
	// rather than passing them to one call: argument evaluation order is
	// unspecified, and the seed must be the pair the first message used to
	// draw so its bytes do not move.
	uint32_t hbhStart = click_random();
	uint32_t e2eStart = click_random();
	ids.seed(hbhStart, e2eStart);
	return 0;
}

Packet* DiameterEncap::simple_action(Packet * p_in)
{
	// Click does not serialise a push element across router threads, so the
	// configured header is copied and filled per packet: two packets must not
	// interleave inside a shared header and stamp one frame with the other
	// packet's Length.
	DiameterHeader header = dh;

	// RFC 6733 section 3 defines the Message Length as the header plus the
	// padded AVPs, so it is always a multiple of 4 and the body is a sequence
	// of already-padded AVPs. A payload that is not on that boundary cannot be
	// such a sequence, and padding it would repair bytes that are not a
	// message into a frame that looks like one -- exactly what this package's
	// own readers then reject. Drop it instead and leave the caller to build
	// the body with DiameterAvpEncap.
	const uint32_t payloadLength = p_in->length();
	if ((payloadLength & 3u) != 0)
	{
		click_chatter("%s: dropping packet: the payload length is not a multiple of 4, so it cannot be a sequence of padded AVPs (RFC 6733 section 3)", class_name());
		p_in->kill();
		return 0;
	}
	// RFC 6733 section 3 fixes the Message Length at three octets. A payload
	// that cannot fit is dropped with its own warning: the header would
	// otherwise wrap and declare a length the frame does not have. The guard
	// runs before the counters so a dropped packet consumes no identifier, and
	// before push() so the drop prints no Put advisory.
	if (payloadLength > DIAMETER_MAX_24BIT_VALUE - DIAMETER_MESSAGE_HEADER_LENGTH)
	{
		click_chatter("%s: dropping packet: the message Length would exceed the three-octet field (RFC 6733 section 3)", class_name());
		p_in->kill();
		return 0;
	}
	header.setLength(DIAMETER_MESSAGE_HEADER_LENGTH + payloadLength);

	// The extension can fail: Click returns a null packet and frees the
	// current one when it cannot allocate the copy. Drop the packet rather than
	// dereference the result. The identifiers advance only after this check,
	// so a packet that is never emitted consumes no identifier.
	WritablePacket* wp = p_in->push(DIAMETER_MESSAGE_HEADER_LENGTH);
	if (!wp)
		return 0;
	// The identifiers come from the two counters, not from the RNG, so each is
	// unique for the first 2^32 messages of the run. The counters are atomic,
	// so two router threads never share a value.
	header.setHbh(ids.nextHbh());
	header.setE2e(ids.nextE2e());
	header.encode(wp->data());

	return wp;
}

CLICK_ENDDECLS
EXPORT_ELEMENT(DiameterEncap)
