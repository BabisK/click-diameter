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
#include <click/sync.hh>

#if defined(__SANITIZE_THREAD__)
# define PSP_TSAN 1
#elif defined(__has_feature)
# if __has_feature(thread_sanitizer)
#  define PSP_TSAN 1
# endif
#endif

#ifdef PSP_TSAN
// Click's Spinlock is an inline-assembly xchg loop, so ThreadSanitizer cannot
// see the lock being taken and would report the store write and the packet that
// reads it as a race even though the xchg orders them. Announce the critical
// section to the sanitizer; a racing access to ah or data is still reported on
// the package's own line.
# include <sanitizer/tsan_interface.h>
# define PSP_TSAN_ACQUIRE(lock) __tsan_acquire(&(lock))
# define PSP_TSAN_RELEASE(lock) __tsan_release(&(lock))
#else
# define PSP_TSAN_ACQUIRE(lock) ((void) 0)
# define PSP_TSAN_RELEASE(lock) ((void) 0)
#endif

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
	uint32_t lastAvpOffset;
	DiameterCheck check = diameter_check_message(p->data(), p->length(),
			&lastAvpOffset);
	if (check != DIAMETER_CHECK_OK)
	{
		click_chatter("%s: dropping malformed packet: %s", class_name(),
				diameter_check_reason(check));
		p->kill();
		return;
	}

	int port;

	// Validation above is pure over the buffer and takes no lock. The store
	// decision and the rewrite it decides are one critical section, so the
	// packet that arrives while an AVP is stored appends it whichever thread
	// delivers either packet; process() runs under the lock and the push
	// happens after the release, so no downstream element runs under it.
	lock.acquire();
	PSP_TSAN_ACQUIRE(lock);
	port = data == NULL ? 0 : 1;
	p = process(p, lastAvpOffset);
	PSP_TSAN_RELEASE(lock);
	lock.release();

	if (p)
	{
		output(port).push(p);
	}
}

Packet* DiameterPopStorePushAVP::process(Packet * p_in, uint32_t lastAvpOffset)
{
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
		// Decode into a local header and publish it under the lock only once
		// the value is copied. data is assigned last: while it is NULL the
		// store is unarmed, so a header is never published without a value.
		AvpHeader ah;
		ah.decode(lastAvp);
		uint32_t headerLength = ah.getHeaderLength();
		uint8_t* storedData = new uint8_t[ah.getLength() - headerLength];
		memcpy(storedData, lastAvp + headerLength, ah.getLength() - headerLength);
		this->ah = ah;
		data = storedData;
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
