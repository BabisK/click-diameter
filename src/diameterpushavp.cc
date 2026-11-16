/*
 * diameterpushavp.{cc,hh} -- element that puts an AVP at the end of the packet
 * Charalampos "Babis" Kaidos
 */

#include <click/config.h>
#include "diameterpushavp.hh"
#include <click/args.hh>
#include <click/confparse.hh>
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
: datastring(), datauint(0), randUInt32(false), randAlphaNumString(0), randNumString(0), randAlphaString(0), randHexString(0) {}

int DiameterPushAVP::configure(Vector<String> &conf, ErrorHandler *errh)
{
	uint32_t code;
	// VENDORSPEC defaults to false. It stays that way when the argument is
	// absent, so initialize it rather than read an indeterminate stack slot
	// that decides whether the AVP gets a 12-octet vendor header.
	bool vendorSpec = false;
	uint32_t vendorId;

	if (Args(conf, this, errh)
		.read_m("CODE", code)
		.read("VENDORSPEC", vendorSpec)
		.read("VENDOR", vendorId)
		.read("OCTETSTRING", datastring)
		.read("UINT32", datauint)
		.read("RANDUINT32", randUInt32)
		.read("RANDALPHANUMSTRING", randAlphaNumString)
		.read("RANDNUMSTRING", randNumString)
		.read("RANDALPHASTRING", randAlphaString)
		.read("RANDHEXSTRING", randHexString)
		.complete() < 0)
		return -1;

	ah.setCode(code);
	ah.setMandatory(false);
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

	if(randUInt32 == true)
	{
		datauint = click_random();
	}
	else if(randAlphaNumString > 0)
	{
		datastring = randString(AlphaNum, randAlphaNumString);
	}
	else if(randNumString > 0)
	{
		datastring = randString(Num, randNumString);
	}
	else if(randAlphaString > 0)
	{
		datastring = randString(Alpha, randAlphaString);
	}
	else if(randHexString > 0)
	{
		datastring = randString(Hex, randHexString);
	}

	// The guard just proved that the header Length equals the packet length,
	// so the message ends exactly where the packet ends.
	const uint32_t messageLength = p_in->length();
	uint32_t avpHeaderLength = ah.getHeaderLength();
	uint32_t avpDataLength = datastring.length() > 0 ? datastring.length() : (datauint > 0 ? 4 : 0);
	uint32_t avpLength = avpHeaderLength + avpDataLength;
	uint32_t avpLengthPadded = ((avpLength + 3) / 4) * 4;
	WritablePacket *p = p_in->put(avpLengthPadded);

	DiameterHeader dh;
	dh.decode(p->data());

	memset(p->data() + messageLength, 0, avpLengthPadded);

	ah.setLength(avpLength);
	ah.encode(p->data() + messageLength);
	if(datastring.length() > 0)
	{
		memcpy(p->data() + messageLength + avpHeaderLength, datastring.data(), avpDataLength);
	}
	else
	{
		uint32_t hton = htonl(datauint);
		memcpy(p->data() + messageLength + avpHeaderLength, &hton, avpDataLength);
	}

	dh.setLength(messageLength + ah.getLengthPadded());
	dh.encode(p->data());

	return p;
}

CLICK_ENDDECLS
EXPORT_ELEMENT(DiameterPushAVP)
