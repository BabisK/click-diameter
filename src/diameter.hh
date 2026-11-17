/*
 * diameter.{cc,hh} -- header for basic Diameter (IETF RFC 6733) structures
 * Charalampos "Babis" Kaidos
 */

#ifndef DIAMETER_HH_
#define DIAMETER_HH_

#include <stdint.h>

// Wire-format sizes shared by every element that reads or writes a Diameter
// frame.
enum : uint32_t {
	DIAMETER_MESSAGE_HEADER_LENGTH = 20,
	DIAMETER_AVP_HEADER_LENGTH = 8,
	// The largest value a three-octet field holds. RFC 6733 section 3 sizes
	// both the message Length and the Command Code at three octets, so a
	// larger value cannot be written. DiameterEncap and DiameterRatedSource
	// refuse a CODE above it at configure time, and DiameterPushAVP drops a
	// packet whose append would grow the message past it.
	DIAMETER_MAX_24BIT_VALUE = 0xFFFFFF
};

class DiameterHeader {
private:
	uint8_t version;
	uint32_t length;
	bool request;
	bool proxiable;
	bool error;
	bool retransmitted;
	uint32_t code;
	uint32_t appId;
	uint32_t hbh;
	uint32_t e2e;

public:
	DiameterHeader() :
			version(1),
			length(DIAMETER_MESSAGE_HEADER_LENGTH),
			request(false),
			proxiable(false),
			error(false),
			retransmitted(false),
			code(0),
			appId(0),
			hbh(0),
			e2e(0) {
	}

	void setVersion(uint8_t version) {
		this->version = version;
	}

	uint8_t getVersion() const {
		return version;
	}

	uint32_t getAppId() const {
		return appId;
	}

	void setAppId(uint32_t appId) {
		this->appId = appId;
	}

	uint32_t getCode() const {
		return code;
	}

	void setCode(uint32_t code) {
		this->code = code;
	}

	uint32_t getE2e() const {
		return e2e;
	}

	void setE2e(uint32_t e2e) {
		this->e2e = e2e;
	}

	bool isError() const {
		return error;
	}

	void setError(bool error) {
		this->error = error;
	}

	uint32_t getHbh() const {
		return hbh;
	}

	void setHbh(uint32_t hbh) {
		this->hbh = hbh;
	}

	uint32_t getLength() const {
		return length;
	}

	void setLength(uint32_t length) {
		this->length = length;
	}

	bool isProxiable() const {
		return proxiable;
	}

	void setProxiable(bool proxiable) {
		this->proxiable = proxiable;
	}

	bool isRequest() const {
		return request;
	}

	void setRequest(bool request) {
		this->request = request;
	}

	bool isRetransmitted() const {
		return retransmitted;
	}

	void setRetransmitted(bool retransmitted) {
		this->retransmitted = retransmitted;
	}

	void decode(const uint8_t* buffer) {
		version = buffer[0];
		length = ((buffer[1] << 16) & 0x00FF0000)
				| ((buffer[2] << 8) & 0x0000FF00) | (buffer[3] & 0x000000FF);
		request = buffer[4] >> 7;
		proxiable = (buffer[4] >> 6) & 0x1;
		error = (buffer[4] >> 5) & 0x1;
		retransmitted = (buffer[4] >> 4) & 0x1;
		code = ((buffer[5] << 16) & 0x00FF0000)
				| ((buffer[6] << 8) & 0x0000FF00) | (buffer[7] & 0x000000FF);
		appId = ((buffer[8] << 24) & 0xFF000000)
				| ((buffer[9] << 16) & 0x00FF0000)
				| ((buffer[10] << 8) & 0x0000FF00) | (buffer[11] & 0x000000FF);
		hbh = ((buffer[12] << 24) & 0xFF000000)
				| ((buffer[13] << 16) & 0x00FF0000)
				| ((buffer[14] << 8) & 0x0000FF00) | (buffer[15] & 0x000000FF);
		e2e = ((buffer[16] << 24) & 0xFF000000)
				| ((buffer[17] << 16) & 0x00FF0000)
				| ((buffer[18] << 8) & 0x0000FF00) | (buffer[19] & 0x000000FF);
	}

	void encode(uint8_t* buffer) {
		memset(buffer, 0, DIAMETER_MESSAGE_HEADER_LENGTH);
		buffer[0] = version;
		buffer[1] = (length >> 16) & 0xFF;
		buffer[2] = (length >> 8) & 0xFF;
		buffer[3] = length & 0xFF;
		buffer[4] = (request << 7) | (proxiable << 6) | (error << 5)
				| (retransmitted << 4);
		buffer[5] = (code >> 16) & 0xFF;
		buffer[6] = (code >> 8) & 0xFF;
		buffer[7] = code & 0xFF;
		buffer[8] = (appId >> 24) & 0xFF;
		buffer[9] = (appId >> 16) & 0xFF;
		buffer[10] = (appId >> 8) & 0xFF;
		buffer[11] = appId & 0xFF;
		buffer[12] = (hbh >> 24) & 0xFF;
		buffer[13] = (hbh >> 16) & 0xFF;
		buffer[14] = (hbh >> 8) & 0xFF;
		buffer[15] = hbh & 0xFF;
		buffer[16] = (e2e >> 24) & 0xFF;
		buffer[17] = (e2e >> 16) & 0xFF;
		buffer[18] = (e2e >> 8) & 0xFF;
		buffer[19] = e2e & 0xFF;
	}
};

class AvpHeader {
private:
	uint32_t code;
	bool vendorSpecific;
	bool mandatory;
	uint32_t length;
	uint32_t vendorId;

public:
	AvpHeader() :
			code(0), vendorSpecific(false), mandatory(false), length(0), vendorId(
					0) {
	}

	uint32_t getCode() const {
		return code;
	}

	void setCode(uint32_t code) {
		this->code = code;
	}

	uint32_t getLength() const {
		return length;
	}

	void setLength(uint32_t length) {
		this->length = length;
	}

	bool getMandatory() const {
		return mandatory;
	}

	void setMandatory(bool mandatory) {
		this->mandatory = mandatory;
	}

	uint32_t getVendorId() const {
		return vendorId;
	}

	void setVendorId(uint32_t vendorId) {
		this->vendorId = vendorId;
	}

	bool getVendorSpecific() const {
		return vendorSpecific;
	}

	void setVendorSpecific(bool vendorSpecific) {
		this->vendorSpecific = vendorSpecific;
	}

	uint32_t getLengthPadded() const {
		return (((this->length + 3) / 4) * 4);
	}

	uint32_t getHeaderLength() const {
		return vendorSpecific ? 12 : 8;
	}

	void decode(const uint8_t* buffer) {
		code = ((buffer[0] << 24) & 0xFF000000)
				| ((buffer[1] << 16) & 0x00FF0000)
				| ((buffer[2] << 8) & 0x0000FF00) | (buffer[3] & 0x000000FF);
		vendorSpecific = (buffer[4] >> 7) & 0x1;
		mandatory = (buffer[4] >> 6) & 0x1;
		length = ((buffer[5] << 16) & 0x00FF0000)
				| ((buffer[6] << 8) & 0x0000FF00) | (buffer[7] & 0x000000FF);
		if (vendorSpecific) {
			vendorId = ((buffer[8] << 24) & 0xFF000000)
					| ((buffer[9] << 16) & 0x00FF0000)
					| ((buffer[10] << 8) & 0x0000FF00)
					| (buffer[11] & 0x000000FF);
		} else {
			vendorId = 0;
		}
	}

	void encode(uint8_t* buffer) {
		if (vendorSpecific) {
			memset(buffer, 0, 12);
		} else {
			memset(buffer, 0, 8);
		}

		buffer[0] = (code >> 24) & 0xFF;
		buffer[1] = (code >> 16) & 0xFF;
		buffer[2] = (code >> 8) & 0xFF;
		buffer[3] = code & 0xFF;
		buffer[4] = (vendorSpecific << 7) | (mandatory << 6);
		buffer[5] = (length >> 16) & 0xFF;
		buffer[6] = (length >> 8) & 0xFF;
		buffer[7] = length & 0xFF;
		if (vendorSpecific) {
			buffer[8] = (vendorId >> 24) & 0xFF;
			buffer[9] = (vendorId >> 16) & 0xFF;
			buffer[10] = (vendorId >> 8) & 0xFF;
			buffer[11] = vendorId & 0xFF;
		}
	}
};

// Why a buffer failed validation. Each element drops the packet and prints one
// click_chatter line with the matching reason.
enum DiameterCheck {
	DIAMETER_CHECK_OK = 0,
	DIAMETER_CHECK_BAD_VERSION,
	DIAMETER_CHECK_SHORT_MESSAGE_HEADER,
	DIAMETER_CHECK_SHORT_AVP_HEADER,
	DIAMETER_CHECK_SHORT_VENDOR_AVP_HEADER,
	DIAMETER_CHECK_LENGTH_NOT_ALIGNED,
	DIAMETER_CHECK_LENGTH_MISMATCH,
	DIAMETER_CHECK_AVP_BELOW_HEADER,
	DIAMETER_CHECK_AVP_PAST_END,
	DIAMETER_CHECK_VENDOR_ID_ZERO,
	DIAMETER_CHECK_ERROR_ON_REQUEST,
	DIAMETER_CHECK_RETRANSMITTED_ON_ANSWER
};

inline const char *diameter_check_reason(DiameterCheck check)
{
	switch (check) {
	case DIAMETER_CHECK_OK:
		return "no error";
	case DIAMETER_CHECK_BAD_VERSION:
		return "the Version field is not 1";
	case DIAMETER_CHECK_SHORT_MESSAGE_HEADER:
		return "packet shorter than the 20-octet Diameter header";
	case DIAMETER_CHECK_SHORT_AVP_HEADER:
		return "packet shorter than the 8-octet AVP header";
	case DIAMETER_CHECK_SHORT_VENDOR_AVP_HEADER:
		return "packet shorter than the 12-octet vendor AVP header";
	case DIAMETER_CHECK_LENGTH_NOT_ALIGNED:
		return "the Length field is not a multiple of 4";
	case DIAMETER_CHECK_LENGTH_MISMATCH:
		return "header Length does not match packet length";
	case DIAMETER_CHECK_AVP_BELOW_HEADER:
		return "AVP length below its header";
	case DIAMETER_CHECK_AVP_PAST_END:
		return "AVP extends past the message end";
	case DIAMETER_CHECK_VENDOR_ID_ZERO:
		return "the V bit is set with a zero Vendor-Id";
	case DIAMETER_CHECK_ERROR_ON_REQUEST:
		return "the E bit is set on a request";
	case DIAMETER_CHECK_RETRANSMITTED_ON_ANSWER:
		return "the T bit is set on an answer";
	}
	return "unknown validation error";
}

// Checks the Diameter header at buffer[0..length): the Version is tested first,
// whenever at least one octet is present, so a frame that disagrees is reported
// as such before the whole-header or Length check; the rest of the checks
// require a whole 20-octet header whose Length field is a multiple of 4 and
// equals length and whose flags are legal for its message type. Elements that
// only touch the header stop here.
inline DiameterCheck diameter_check_header(const uint8_t *buffer, uint32_t length)
{
	// RFC 6733 section 3 fixes the Version at 1, so a frame that disagrees is
	// not a Diameter message at any length. Testing it first keeps the Version
	// reason ahead of a Length or framing fault; the length guard keeps a
	// zero-octet packet from being read out of bounds.
	if (length >= 1 && buffer[0] != 1)
		return DIAMETER_CHECK_BAD_VERSION;
	if (length < DIAMETER_MESSAGE_HEADER_LENGTH)
		return DIAMETER_CHECK_SHORT_MESSAGE_HEADER;
	const uint32_t declared = ((uint32_t) buffer[1] << 16)
			| ((uint32_t) buffer[2] << 8) | buffer[3];
	// RFC 6733 section 3: the Message Length covers the header and the padded
	// AVPs, so it is always a multiple of 4. A Length that is not cannot
	// describe a Diameter message at any packet length, so it is reported
	// before the comparison against this packet; the short-header guard above
	// already proved the three octets are readable.
	if ((declared & 3u) != 0)
		return DIAMETER_CHECK_LENGTH_NOT_ALIGNED;
	if (declared != length)
		return DIAMETER_CHECK_LENGTH_MISMATCH;
	// RFC 6733 section 3: E MUST NOT be set in request messages and T MUST NOT
	// be set in answer messages. The R bit selects the message type, and P is
	// legal on either, so it is not tested here.
	const uint8_t flags = buffer[4];
	if ((flags & 0x20) && (flags & 0x80))
		return DIAMETER_CHECK_ERROR_ON_REQUEST;
	if ((flags & 0x10) && !(flags & 0x80))
		return DIAMETER_CHECK_RETRANSMITTED_ON_ANSWER;
	return DIAMETER_CHECK_OK;
}

// Checks one AVP at buffer[0..length): the V bit decides whether its header is
// 8 or 12 octets, the header must fit, and the declared length must be at least
// that header and at most the octets available. A 12-octet vendor header must
// also carry a non-zero Vendor-Id, which RFC 6733 section 4.1.1 requires when V
// is set. Padding is not required here: a standalone AVP may legitimately
// arrive without its zero pad, because the pad belongs to the message a
// receiver walks, not to the AVP's own Length. The decoder strips only what
// Length says, and the message walk applies its own padded bound. On success
// *header_length is the header size and *avp_length the declared length.
inline DiameterCheck diameter_check_avp(const uint8_t *buffer, uint32_t length,
		uint32_t *header_length, uint32_t *avp_length)
{
	if (length < DIAMETER_AVP_HEADER_LENGTH)
		return DIAMETER_CHECK_SHORT_AVP_HEADER;
	const uint32_t headerLength = (buffer[4] & 0x80) ? 12 : 8;
	if (length < headerLength)
		return DIAMETER_CHECK_SHORT_VENDOR_AVP_HEADER;
	const uint32_t avpLength = ((uint32_t) buffer[5] << 16)
			| ((uint32_t) buffer[6] << 8) | buffer[7];
	if (avpLength < headerLength)
		return DIAMETER_CHECK_AVP_BELOW_HEADER;
	if (avpLength > length)
		return DIAMETER_CHECK_AVP_PAST_END;
	// The 12-octet header guard above proves bytes 8 to 11 are readable. The
	// Length checks come first so a frame whose Length already contradicts its
	// header keeps that reason.
	if (headerLength == 12
			&& buffer[8] == 0 && buffer[9] == 0
			&& buffer[10] == 0 && buffer[11] == 0)
		return DIAMETER_CHECK_VENDOR_ID_ZERO;
	*header_length = headerLength;
	*avp_length = avpLength;
	return DIAMETER_CHECK_OK;
}

// Checks whether buffer[0..length) holds exactly one well-formed Diameter
// message: a header that passes diameter_check_header() -- Version 1, a Length
// field that is a multiple of 4 and equal to length, and legal flags -- then a
// run of AVPs that each pass diameter_check_avp() and whose padded lengths stay
// inside the message, so the walk always advances. On success *last_avp_offset
// is the offset of the final AVP, or 0 when the message has none; pass 0 when
// the caller does not need it.
inline DiameterCheck diameter_check_message(const uint8_t *buffer,
		uint32_t length, uint32_t *last_avp_offset)
{
	const DiameterCheck headerCheck = diameter_check_header(buffer, length);
	if (headerCheck != DIAMETER_CHECK_OK)
		return headerCheck;

	uint32_t offset = DIAMETER_MESSAGE_HEADER_LENGTH;
	uint32_t lastAvp = 0;
	while (offset < length) {
		uint32_t headerLength;
		uint32_t avpLength;
		const DiameterCheck check = diameter_check_avp(buffer + offset,
				length - offset, &headerLength, &avpLength);
		if (check != DIAMETER_CHECK_OK)
			return check;
		const uint32_t paddedLength = (avpLength + 3) & ~3u;
		if (paddedLength > length - offset)
			return DIAMETER_CHECK_AVP_PAST_END;
		lastAvp = offset;
		offset += paddedLength;
	}

	if (last_avp_offset)
		*last_avp_offset = lastAvp;
	return DIAMETER_CHECK_OK;
}

#endif /* DIAMETER_HH_ */
