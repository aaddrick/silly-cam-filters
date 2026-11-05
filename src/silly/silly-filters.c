/*
 * Registers our own filters. Add one line here for each new filter.
 */
#include <obs-module.h>

#include "scf-family.h"

extern struct obs_source_info silly_mirror_filter;

void scf_silly_register(void)
{
	obs_register_source(&silly_mirror_filter);
}
