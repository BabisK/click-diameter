/*
 * diameterencap.{cc,hh} -- element that puts a Diameter header on the packet
 * Charalampos "Babis" Kaidos
 */

#ifndef DIAMETERENCAP_HH_
#define DIAMETERENCAP_HH_
#include <click/element.hh>
#include "diameter.hh"
CLICK_DECLS

/*
=c

DiameterEncap(CODE, REQUEST [, ERROR, PROXIABLE, RETRANSMITED, APPID])

=s basictransfer

prepends a Diameter header to each packet

=d

Prepends a 20-octet Diameter header to every incoming packet. The header
carries version 1, Length 20 plus the payload, the Command Code CODE, the
Application-Id APPID, and hop-by-hop and end-to-end identifiers. Each
identifier is seeded once from click_random() when the element is initialized and
then advanced by one for every message the element emits, so each field is unique
for the first 2^32 messages of a run and RandomSeed reproduces the sequence byte
for byte. The end-to-end field is a plain 32-bit counter; its high-order 12 bits
advance when the low-order 20 bits wrap. RFC 6733 section 3 permits, but does not
require, a reboot-time value in the high half and a random value in the low half
on a new run; this element uses neither, and the seed chooses both starting
values. A new run starts a new sequence from its seed; nothing is claimed across
reboots.

RFC 6733 section 3 defines the Message Length as the header plus the padded
AVPs, so it is always a multiple of 4 and the body is a sequence of padded AVPs.
The element does not interpret the payload: a payload already on that boundary is
forwarded unchanged and keeps its Length, while a payload that is not on it is
dropped with C<DiameterEncap: dropping packet: the payload length is not a
multiple of 4, so it cannot be a sequence of padded AVPs (RFC 6733 section 3)>
rather than zero-padded into a frame that only looks like a message. A zero-octet
packet is legal (the message has no AVPs). A body that happens to be aligned but
is not AVPs is forwarded as given and dropped by whichever AVP reader follows;
build a conformant body with DiameterAvpEncap.

CODE and REQUEST are required. The flags start clear and only the arguments the
caller names are set: E from ERROR, P from PROXIABLE and T from RETRANSMITED.
RFC 6733 section 3 forbids E in a request and T in an answer, so a configuration
that sets ERROR on a request or RETRANSMITED on an answer is rejected while the
element is configured, with an error naming the argument. PROXIABLE is accepted
on either type: section 6.2 mirrors a request's P into its answer, and this
element has no request to consult, so the caller's declaration stands.

The Command Code field is three octets (RFC 6733 section 3), so CODE must not
exceed 0xFFFFFF: a larger value fails configuration with an error naming the
argument rather than being truncated on the wire. The two experimental values
that section 3.1 reserves, 0xFFFFFE and 0xFFFFFF, are in range. The Message
Length is three octets too, so a payload that cannot fit is dropped with
C<DiameterEncap: dropping packet: the message Length would exceed the three-octet
field (RFC 6733 section 3)> rather than emitted with a wrapped field, and a
dropped packet consumes no identifier. A keyword repeated in one configuration
fails configuration too, with C<the CODE argument is given more than once>,
rather than silently keeping the last value.

The element does not validate the incoming packet; it is a writer, not a
reader.

Keyword arguments are:

=over 8

=item CODE

Integer. Required. The Command Code written into the header. Must not exceed
0xFFFFFF, the largest value the three-octet field holds (RFC 6733 section 3);
a larger value fails configuration.

=item REQUEST

Boolean. Required. True writes a request, false writes an answer.

=item ERROR

Boolean. Sets the E bit. Legal only on an answer, and rejected on a request.
Default is false.

=item PROXIABLE

Boolean. Sets the P bit. Legal on either type. Default is false.

=item RETRANSMITED

Boolean. Sets the T bit. Legal only on a request, and rejected on an answer.
Default is false.

=item APPID

Integer. Application-Id written into the header. Default is 0.

=back

=a

DiameterDecap, DiameterRatedSource, DiameterFlipRequest
*/

class DiameterEncap : public Element
{
public:
	DiameterEncap() CLICK_COLD;

	const char *class_name() const		{ return "DiameterEncap"; }
    const char *port_count() const		{ return PORTS_1_1; }

    int configure(Vector<String> &conf, ErrorHandler *errh) CLICK_COLD;
    int initialize(ErrorHandler *errh) CLICK_COLD;
    Packet *simple_action(Packet * p_in);

private:
    // Configuration only: configure() fills it, and simple_action() copies it
    // into a local header per packet instead of writing it.
    DiameterHeader dh;

    // Seeded in initialize(), advanced once per emitted message: the data path
    // never draws from the RNG.
    DiameterIdentifierCounter ids;
};

CLICK_ENDDECLS
#endif /* DIAMETERENCAP_HH_ */
