/*
 * diameterpushavp.{cc,hh} -- element that puts an AVP at the end of the packet
 * Charalampos "Babis" Kaidos
 */

#include <click/config.h>
#include "diameterpushavp.hh"
#include <click/args.hh>
#include <click/confparse.hh>
#include <click/error.hh>
#include <click/glue.hh>
CLICK_DECLS

enum randStringType{
	AlphaNum,
	Num,
	Alpha,
	Hex
};

static String randString(randStringType type, size_t size)
{
	static const char alphaNum[] =
	        "0123456789"
	        "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	        "abcdefghijklmnopqrstuvwxyz";

	static const char num[] =
	        "0123456789";

	static const char alpha[] =
	        "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	        "abcdefghijklmnopqrstuvwxyz";

	static const char hex[] =
	        "0123456789ABCDEF";

	String ret;
	switch(type)
	{
	case AlphaNum:
		while(size-- > 0)
		{
			ret.append(alphaNum[click_random() % (sizeof(alphaNum)-1)]);
		}
		break;
	case Num:
		while(size-- > 0)
		{
			ret.append(num[click_random() % (sizeof(num)-1)]);
		}
		break;
	case Alpha:
		while(size-- > 0)
		{
			ret.append(alpha[click_random() % (sizeof(alpha)-1)]);
		}
		break;
	case Hex:
		while(size-- > 0)
		{
			ret.append(hex[click_random() % (sizeof(hex)-1)]);
		}
		break;
	}

	return ret;
}

DiameterPushAVP::DiameterPushAVP()
: datastring(), datauint(0), hasUint(false), randUInt32(false), randAlphaNumString(0), randNumString(0), randAlphaString(0), randHexString(0) {}

int DiameterPushAVP::configure(Vector<String> &conf, ErrorHandler *errh)
{
	uint32_t code;
	// VENDORSPEC defaults to false. It stays that way when the argument is
	// absent, so initialize it rather than read an indeterminate stack slot
	// that decides whether the AVP gets a 12-octet vendor header.
	bool vendorSpec = false;
	// Likewise initialize the Vendor-Id: an absent VENDOR must not leak a
	// stack slot into the header, and must be rejected when VENDORSPEC is set.
	uint32_t vendorId = 0;
	// The M bit defaults to clear, so an absent MANDATORY keeps the AVP bytes
	// exactly as they were before the argument existed.
	bool mandatory = false;
	// Whether UINT32 was supplied, which its value cannot say: an absent
	// argument and an explicit UINT32 0 both leave datauint at zero.
	bool uintSpecified = false;
	// Likewise whether OCTETSTRING was supplied: an absent argument and an
	// explicit OCTETSTRING "" both leave datastring empty, and the empty string
	// is the documented no-value request rather than an absence.
	bool octetSpecified = false;

	if (Args(conf, this, errh)
		.read_m("CODE", code)
		.read("VENDORSPEC", vendorSpec)
		.read("VENDOR", vendorId)
		.read("MANDATORY", mandatory)
		.read("OCTETSTRING", datastring).read_status(octetSpecified)
		.read("UINT32", datauint).read_status(uintSpecified)
		.read("RANDUINT32", randUInt32)
		.read("RANDALPHANUMSTRING", randAlphaNumString)
		.read("RANDNUMSTRING", randNumString)
		.read("RANDALPHASTRING", randAlphaString)
		.read("RANDHEXSTRING", randHexString)
		.complete() < 0)
		return -1;

	// At most one value source may supply the value: two of them used to resolve
	// by if/else order, so one was silently discarded and the caller got an AVP
	// of the wrong value type. Presence differs per argument because the parsed
	// value cannot express it: OCTETSTRING counts when the keyword is present
	// (an empty string is the documented no-value request) and UINT32 when
	// present (zero is four octets), RANDUINT32 only when true, and a RAND*STRING
	// generator only when its count is above zero, the documented "unused" value.
	// The walk follows the documented argument order, so a configuration with
	// three sources names a deterministic pair.
	const struct {
		const char *name;
		bool supplied;
	} valueSources[] = {
		{ "OCTETSTRING", octetSpecified },
		{ "UINT32", uintSpecified },
		{ "RANDUINT32", randUInt32 },
		{ "RANDALPHANUMSTRING", randAlphaNumString > 0 },
		{ "RANDNUMSTRING", randNumString > 0 },
		{ "RANDALPHASTRING", randAlphaString > 0 },
		{ "RANDHEXSTRING", randHexString > 0 }
	};
	const char *firstSource = 0;
	for (size_t i = 0; i < sizeof(valueSources) / sizeof(valueSources[0]); ++i)
	{
		if (!valueSources[i].supplied)
		{
			continue;
		}
		if (firstSource)
		{
			return errh->error("the %s and %s arguments cannot be used together: at most one value source may be supplied",
					firstSource, valueSources[i].name);
		}
		firstSource = valueSources[i].name;
	}

	// Presence decides the value length, not magnitude: both sources supply a
	// 4-octet number, and zero is a legal value of each. RFC 6733 section 4.2
	// fixes Unsigned32 at AVP Length 12 (16 with the vendor header).
	hasUint = uintSpecified || randUInt32;

	// RFC 6733 section 4.1.1 forbids Vendor-Id zero with the V bit set, so an
	// absent VENDOR and an explicit VENDOR 0 are the same refusal.
	if (vendorSpec && vendorId == 0)
		return errh->error("the VENDOR argument must be non-zero when VENDORSPEC is true (RFC 6733 section 4.1.1)");

	ah.setCode(code);
	ah.setMandatory(mandatory);
	ah.setVendorSpecific(vendorSpec);
	if(vendorSpec)
	{
		ah.setVendorId(vendorId);
	}
	else
	{
		ah.setVendorId(0);
	}

	return 0;
}

Packet* DiameterPushAVP::simple_action(Packet * p_in)
{
	DiameterCheck check = diameter_check_message(p_in->data(), p_in->length(), 0);
	if (check != DIAMETER_CHECK_OK)
	{
		click_chatter("%s: dropping malformed packet: %s", class_name(),
				diameter_check_reason(check));
		p_in->kill();
		return 0;
	}

	// Click does not serialise a push element across router threads, so the
	// configured value and header are copied per packet: every write below
	// goes to a local, and the members are only read.
	uint32_t valueUint = datauint;
	String valueString = datastring;
	AvpHeader header = ah;

	// configure() admits at most one value source, so at most one branch applies;
	// a new value argument must be added to the presence table in configure().
	if(randUInt32 == true)
	{
		valueUint = click_random();
	}
	else if(randAlphaNumString > 0)
	{
		valueString = randString(AlphaNum, randAlphaNumString);
	}
	else if(randNumString > 0)
	{
		valueString = randString(Num, randNumString);
	}
	else if(randAlphaString > 0)
	{
		valueString = randString(Alpha, randAlphaString);
	}
	else if(randHexString > 0)
	{
		valueString = randString(Hex, randHexString);
	}

	// The guard just proved that the header Length equals the packet length,
	// so the message ends exactly where the packet ends.
	const uint32_t messageLength = p_in->length();
	uint32_t avpHeaderLength = header.getHeaderLength();
	uint32_t avpDataLength = valueString.length() > 0 ? valueString.length() : (hasUint ? 4 : 0);
	uint32_t avpLength = avpHeaderLength + avpDataLength;
	uint32_t avpLengthPadded = ((avpLength + 3) / 4) * 4;
	WritablePacket *p = p_in->put(avpLengthPadded);

	DiameterHeader dh;
	dh.decode(p->data());

	memset(p->data() + messageLength, 0, avpLengthPadded);

	header.setLength(avpLength);
	header.encode(p->data() + messageLength);
	if(valueString.length() > 0)
	{
		memcpy(p->data() + messageLength + avpHeaderLength, valueString.data(), avpDataLength);
	}
	else
	{
		uint32_t hton = htonl(valueUint);
		memcpy(p->data() + messageLength + avpHeaderLength, &hton, avpDataLength);
	}

	dh.setLength(messageLength + header.getLengthPadded());
	dh.encode(p->data());

	return p;
}

CLICK_ENDDECLS
EXPORT_ELEMENT(DiameterPushAVP)
