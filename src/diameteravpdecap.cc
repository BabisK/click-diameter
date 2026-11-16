/*
 * diameteravpdecap.{cc,hh} -- element that removes a Diameter AVP header from the packet
 * Charalampos "Babis" Kaidos
 *
 * Copyright (c) 2014 Intracom Telecom
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, subject to the conditions
 * listed in the Click LICENSE file. These conditions include: you must
 * preserve this copyright notice, and you cannot mention the copyright
 * holders in advertising related to the Software without their permission.
 * The Software is provided WITHOUT ANY WARRANTY, EXPRESS OR IMPLIED. This
 * notice is a summary of the Click LICENSE file; the license in that file is
 * legally binding.
 */

#include <click/config.h>
#include "diameteravpdecap.hh"
#include <click/args.hh>
#include <click/glue.hh>
CLICK_DECLS

DiameterAvpDecap::DiameterAvpDecap(){}

Packet* DiameterAvpDecap::simple_action(Packet * p_in)
{
	uint32_t headerLength;
	uint32_t avpLength;
	DiameterCheck check = diameter_check_avp(p_in->data(), p_in->length(),
			&headerLength, &avpLength);
	if (check != DIAMETER_CHECK_OK)
	{
		click_chatter("%s: dropping malformed packet: %s", class_name(),
				diameter_check_reason(check));
		p_in->kill();
		return 0;
	}
	p_in->pull(headerLength);

	return p_in;
}

CLICK_ENDDECLS
EXPORT_ELEMENT(DiameterAvpDecap)
