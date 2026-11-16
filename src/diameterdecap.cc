/*
 * diameterdecap.{cc,hh} -- element that removes a Diameter header from the packet
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
#include "diameterdecap.hh"
#include <click/args.hh>
#include <click/glue.hh>
CLICK_DECLS

DiameterDecap::DiameterDecap(){}

Packet* DiameterDecap::simple_action(Packet * p_in)
{
	const DiameterCheck check = diameter_check_header(p_in->data(),
			p_in->length());
	if (check != DIAMETER_CHECK_OK)
	{
		click_chatter("%s: dropping malformed packet: %s", class_name(),
				diameter_check_reason(check));
		p_in->kill();
		return 0;
	}
	p_in->pull(DIAMETER_MESSAGE_HEADER_LENGTH);
	return p_in;
}

CLICK_ENDDECLS
EXPORT_ELEMENT(DiameterDecap)
