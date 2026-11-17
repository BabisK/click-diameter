/*
 * diameterratedsource.{cc,hh} -- element that creates packets containing a diameter header,
 * much like the RatedSource() element of the standard package
 * Charalampos "Babis" Kaidos
 */

#ifndef DIAMETERRATEDSOURCE_HH_
#define DIAMETERRATEDSOURCE_HH_
#include <click/element.hh>
#include <click/tokenbucket.hh>
#include <click/task.hh>
#include "diameter.hh"
CLICK_DECLS

/*
=c

DiameterRatedSource(CODE, REQUEST, I<keywords> RATE, LIMIT, ACTIVE, APPID, STOP)

=s basicsources

generates bare Diameter messages at a fixed rate

=d

Creates 20-octet Diameter messages with no AVPs and emits them from its single
output at RATE packets per second. Every message carries version 1, Length 20,
the Command Code CODE and the Application-Id APPID, and hop-by-hop and
end-to-end identifiers. Each identifier is seeded once from click_random() when
the element is initialized and then advanced by one for every message the
element emits, whether the packet leaves through the push task or through pull,
so each field is unique for the first 2^32 messages of a run and RandomSeed
reproduces the sequence byte for byte. The end-to-end field is a plain 32-bit
counter; its high-order 12 bits advance when the low-order 20 bits wrap. RFC
6733 section 3 permits, but does not require, a reboot-time value in the high
half and a random value in the low half on a new run; this element uses neither,
and the seed chooses both starting values. A new run starts a new sequence from
its seed; nothing is claimed across reboots. The E, P and T bits are always
clear, so a generated request carries R alone and a generated answer carries no
flag at all. Nothing is padded: a message without AVPs needs no pad octets.

CODE and REQUEST are required. RATE, LIMIT and ACTIVE may also be given as
positional arguments, in that order; APPID and STOP are optional keywords,
defaulting to 0 and false. When the token bucket runs dry a push element
schedules itself for the time the next packet becomes available, and a pull
element returns a null packet instead.

The Command Code field is three octets (RFC 6733 section 3), so CODE must not
exceed 0xFFFFFF: a larger value fails configuration with an error naming the
argument rather than being truncated on the wire. The two experimental values
that section 3.1 reserves, 0xFFFFFE and 0xFFFFFF, are in range. A keyword
repeated in one configuration fails configuration too, with C<the RATE argument
is given more than once>, rather than silently keeping the last value.

Keyword arguments are:

=over 8

=item CODE

Integer. Required. The Command Code written into every message. Must not exceed
0xFFFFFF, the largest value the three-octet field holds (RFC 6733 section 3);
a larger value fails configuration.

=item REQUEST

Boolean. Required. True generates requests, false generates answers.

=item RATE

Integer. Generation rate in packets per second. Default is 10.

=item LIMIT

Integer. Stop after this many messages. A negative value means no limit, which
is the default.

=item ACTIVE

Boolean. If false the element generates nothing. Default is true.

=item APPID

Integer. Application-Id written into every message. Default is 0.

=item STOP

Boolean. If true, stop the driver once LIMIT messages have been sent. Default
is false. Meaningless when LIMIT is negative.

=back

=h rate read/write

Returns or sets the generation rate in packets per second.

=h limit read/write

Returns or sets the packet limit. A negative value means no limit, and the
handler reports -1 for it.

=h active read/write

Makes the element active or inactive. An inactive element generates nothing.

=h count read-only

Returns the number of messages generated since the last reset.

=h reset write-only

Resets the message count to 0 and refills the token bucket.

=a

DiameterEncap, DiameterPushAVP
*/

class DiameterRatedSource : public Element
{
public:
	DiameterRatedSource() CLICK_COLD;

	const char *class_name() const		{ return "DiameterRatedSource"; }
    const char *port_count() const		{ return PORTS_0_1; }
    void add_handlers() CLICK_COLD;

    int configure(Vector<String> &conf, ErrorHandler *errh) CLICK_COLD;
    int initialize(ErrorHandler *errh) CLICK_COLD;
    void cleanup(CleanupStage) CLICK_COLD;

    bool run_task(Task *task);
    Packet *pull(int);

  protected:

    static const unsigned NO_LIMIT = 0xFFFFFFFFU;

    TokenBucket _tb;
    unsigned _count;
    unsigned _limit;
    bool _active;
    bool _stop;
    uint32_t _code;
    uint32_t _appid;
    Packet *_packet;
    Task _task;
    Timer _timer;
    // Configuration only: run_task() and pull() copy it into a local header and
    // stamp that, so no shared field is written per message.
    DiameterHeader dh;

    // Seeded in initialize(), advanced once per emitted message. Push and pull
    // share one pair of sequences.
    DiameterIdentifierCounter ids;

    void setup_packet();

    static String read_param(Element *, void *) CLICK_COLD;
    static int change_param(const String &, Element *, void *, ErrorHandler *);

};



CLICK_ENDDECLS
#endif /* DIAMETERRATEDSOURCE_HH_ */
