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

Prepends a 20-octet Diameter header to every incoming packet, leaving the
payload untouched. The header carries version 1, Length 20 plus the incoming
packet length, the Command Code CODE, the Application-Id APPID, and hop-by-hop
and end-to-end identifiers drawn from click_random() for each packet. Because
the header is exactly 20 octets, the payload needs no padding.

CODE and REQUEST are required. The flags start clear and only the arguments the
caller names are set: E from ERROR, P from PROXIABLE and T from RETRANSMITED.
RFC 6733 section 3 forbids E in a request and T in an answer, so a configuration
that sets ERROR on a request or RETRANSMITED on an answer is rejected while the
element is configured, with an error naming the argument. PROXIABLE is accepted
on either type: section 6.2 mirrors a request's P into its answer, and this
element has no request to consult, so the caller's declaration stands.

The element does not validate the incoming packet; it is a writer, not a
reader.

Keyword arguments are:

=over 8

=item CODE

Integer. Required. The Command Code written into the header.

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
    Packet *simple_action(Packet * p_in);

private:
    DiameterHeader dh;
};

CLICK_ENDDECLS
#endif /* DIAMETERENCAP_HH_ */
