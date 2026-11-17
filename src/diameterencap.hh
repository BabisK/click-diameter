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
carries version 1, Length 20 plus the padded payload, the Command Code CODE,
the Application-Id APPID, and hop-by-hop and end-to-end identifiers. Each
identifier is seeded once from click_random() when the element is initialized and
then advanced by one for every message the element emits, so each field is unique
for the first 2^32 messages of a run and RandomSeed reproduces the sequence byte
for byte. The end-to-end field keeps RFC 6733 section 3's twelve/twenty split:
its high-order 12 bits are the epoch, which advances when the low-order 20 bits
wrap, and the seed chooses the starting epoch rather than the clock. A new run
starts a new sequence from its seed; nothing is claimed across reboots. RFC 6733
section 3 requires the Message Length to be a multiple of 4, so the payload is
zero-padded up to a 4-octet boundary and the pad octets count in the Length: a
5-octet payload gains three zero pad octets and Length 28, while a payload
already on the boundary gains none and keeps its bytes. The pad is part of the
message, so DiameterDecap forwards it along with the payload.

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
section 3.1 reserves, 0xFFFFFE and 0xFFFFFF, are in range.

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
