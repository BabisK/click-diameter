/*
 * diameterratedsource.{cc,hh} -- element that creates packets containing a diameter header,
 * much like the RatedSource() element of the standard package
 * Charalampos "Babis" Kaidos
 */

#include <click/config.h>
#include "diameterratedsource.hh"
#include "diameterconf.hh"
#include <click/args.hh>
#include <click/error.hh>
#include <click/router.hh>
#include <click/straccum.hh>
#include <click/standard/scheduleinfo.hh>
#include <click/glue.hh>
CLICK_DECLS

const unsigned DiameterRatedSource::NO_LIMIT;

DiameterRatedSource::DiameterRatedSource()
  : _packet(0), _task(this), _timer(&_task)
{
}

int
DiameterRatedSource::configure(Vector<String> &conf, ErrorHandler *errh)
{
    String data =
	"Random bullshit in a packet, at least 64 bytes long. Well, now it is.";
    unsigned rate = 10;
    int limit = -1;
    bool active = true, stop = false;
    uint32_t code = 0;
    uint32_t appid = 0;
    bool request;

    static const char *const keywords[] = {
	"RATE", "LIMIT", "ACTIVE", "CODE", "REQUEST", "APPID", "STOP"
    };
    if (diameter_reject_duplicate_keywords(conf, errh, keywords,
		sizeof(keywords) / sizeof(keywords[0])) < 0)
	return -1;

    if (Args(conf, this, errh)
	.read_p("RATE", rate)
	.read_p("LIMIT", limit)
	.read_p("ACTIVE", active)
	.read_m("CODE", code)
	.read_m("REQUEST", request)
	.read("APPID", appid)
	.read("STOP", stop)
	.complete() < 0)
	return -1;

    // RFC 6733 section 3 fixes the Command Code at three octets, so a larger
    // value cannot be encoded: 0x01000118 would go out as 0x000118, a different
    // message type. Refuse the configuration instead of truncating it; the
    // experimental 0xFFFFFE and 0xFFFFFF of section 3.1 stay in range.
    if (code > DIAMETER_MAX_24BIT_VALUE)
	return errh->error("the CODE argument must not exceed 0xFFFFFF: the Command Code field is three octets (RFC 6733 section 3)");

    int burst = rate < 200 ? 2 : rate / 100;
    _tb.assign(rate, burst);
    _limit = (limit >= 0 ? unsigned(limit) : NO_LIMIT);
    _active = active;
    _stop = stop;
    _code = code;
    _appid = appid;

    dh.setVersion(1);
    dh.setLength(DIAMETER_MESSAGE_HEADER_LENGTH);
    dh.setRequest(request);
    dh.setCode(_code);
    dh.setAppId(_appid);

    setup_packet();

    return 0;
}

int
DiameterRatedSource::initialize(ErrorHandler *errh)
{
    // Seed once, after every element has been configured, so RandomSeed has
    // already applied its seed wherever its statement sits. Name the two draws
    // rather than passing them to one call: argument evaluation order is
    // unspecified, and the seed must be the pair the first message used to
    // draw so its bytes do not move.
    uint32_t hbhStart = click_random();
    uint32_t e2eStart = click_random();
    ids.seed(hbhStart, e2eStart);

    _count = 0;
    if (output_is_push(0))
	ScheduleInfo::initialize_task(this, &_task, errh);
    _tb.set(1);
    _timer.initialize(this);
    return 0;
}

void
DiameterRatedSource::cleanup(CleanupStage)
{
    if (_packet)
	_packet->kill();
    _packet = 0;
}

bool
DiameterRatedSource::run_task(Task *)
{
    if (!_active)
	return false;
    if (_limit != NO_LIMIT && _count >= _limit) {
	if (_stop)
	    router()->please_stop_driver();
	return false;
    }

    _tb.refill();
    if (_tb.remove_if(1)) {
	// Copy the configured header and stamp the identifiers only for a message
	// that is actually emitted: a token-bucket refusal must not consume a
	// counter value, so push and pull share one sequence and neither skips a
	// value. The local copy keeps a task and a pull from writing one header.
	DiameterHeader header = dh;
	// Both allocation steps can fail and free what they hold; a packet that is
	// never emitted must not leave the router with a null dereference. The
	// counters advance only after them, so a failed allocation consumes no
	// identifier.
	Packet *p = _packet->clone();
	if (!p)
	    return false;
	p->set_timestamp_anno(Timestamp::now());
	WritablePacket *wp = p->put(0);
	if (!wp)
	    return false;
	header.setHbh(ids.nextHbh());
	header.setE2e(ids.nextE2e());
	wp->set_timestamp_anno(Timestamp::now());
	header.encode(wp->data());
	output(0).push(wp);
	_count++;
	_task.fast_reschedule();
	return true;
    } else {
	// Convert through the bucket's own parameter type: upstream Click's
	// TokenBucket ticks in jiffies, FastClick's in microseconds, and only
	// parameter_type::timestamp() follows whichever unit this build uses. A
	// cast to click_jiffies_t compiles against both but reads FastClick's
	// microseconds as jiffies, so the timer would wait 1000 times too long.
	_timer.schedule_after(TokenBucket::parameter_type::timestamp(_tb.time_until_contains(1)));
	return false;
    }
}

Packet *
DiameterRatedSource::pull(int)
{
    if (!_active)
	return 0;
    if (_limit != NO_LIMIT && _count >= _limit) {
	if (_stop)
	    router()->please_stop_driver();
	return 0;
    }

    _tb.refill();
    if (_tb.remove_if(1)) {
	// The same counters the push task uses, stepped once for this returned
	// packet only: a refusal above consumed nothing.
	DiameterHeader header = dh;
	// Same guards as the task path: a failed clone or extension returns no
	// packet instead of dereferencing null, and consumes no identifier.
	Packet *p = _packet->clone();
	if (!p)
	    return 0;
	p->set_timestamp_anno(Timestamp::now());
	WritablePacket *wp = p->put(0);
	if (!wp)
	    return 0;
	header.setHbh(ids.nextHbh());
	header.setE2e(ids.nextE2e());
	wp->set_timestamp_anno(Timestamp::now());
	header.encode(wp->data());
	_count++;
	return wp;
    } else
	return 0;
}

void
DiameterRatedSource::setup_packet()
{
    if (_packet)
	_packet->kill();

    // note: if you change `headroom', change `click-align'
    unsigned int headroom = 16+20+24;

    uint8_t data[DIAMETER_MESSAGE_HEADER_LENGTH] = {0};
    _packet = Packet::make(headroom, reinterpret_cast<unsigned char*>(data),
			   DIAMETER_MESSAGE_HEADER_LENGTH, 0);
}

String
DiameterRatedSource::read_param(Element *e, void *vparam)
{
  DiameterRatedSource *rs = (DiameterRatedSource *)e;
  switch ((intptr_t)vparam) {
   case 1:			// rate
    return String(rs->_tb.rate());
   case 2:			// limit
    return (rs->_limit != NO_LIMIT ? String(rs->_limit) : String("-1"));
   default:
    return "";
  }
}

int
DiameterRatedSource::change_param(const String &s, Element *e, void *vparam,
			  ErrorHandler *errh)
{
	DiameterRatedSource *rs = (DiameterRatedSource *)e;
  switch ((intptr_t)vparam) {

  case 1: {			// rate
      unsigned rate;
      if (!IntArg().parse(s, rate))
	  return errh->error("syntax error");
      rs->_tb.assign_adjust(rate, rate < 200 ? 2 : rate / 100);
      break;
  }

   case 2: {			// limit
     int limit;
     if (!IntArg().parse(s, limit))
       return errh->error("syntax error");
     rs->_limit = (limit >= 0 ? unsigned(limit) : NO_LIMIT);
     break;
   }

  case 3: {			// active
      bool active;
      if (!BoolArg().parse(s, active))
	  return errh->error("syntax error");
      rs->_active = active;
      if (rs->output_is_push(0) && !rs->_task.scheduled() && active) {
	  rs->_tb.set(1);
	  rs->_task.reschedule();
      }
      break;
  }

  case 5: {			// reset
      rs->_count = 0;
      rs->_tb.set(1);
      if (rs->output_is_push(0) && !rs->_task.scheduled() && rs->_active)
	  rs->_task.reschedule();
      break;
  }

  }
  return 0;
}

void
DiameterRatedSource::add_handlers()
{
  add_read_handler("rate", read_param, 1);
  add_write_handler("rate", change_param, 1);
  add_read_handler("limit", read_param, 2, Handler::CALM);
  add_write_handler("limit", change_param, 2);
  add_data_handlers("active", Handler::OP_READ | Handler::CHECKBOX, &_active);
  add_write_handler("active", change_param, 3);
  add_data_handlers("count", Handler::OP_READ, &_count);
  add_write_handler("reset", change_param, 5, Handler::BUTTON);

  if (output_is_push(0))
    add_task_handlers(&_task);
}

CLICK_ENDDECLS
EXPORT_ELEMENT(DiameterRatedSource)
