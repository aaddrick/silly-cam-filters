/*
 * silly-cam-filters: the one OBS module that loads every filter family.
 *
 * OBS calls the hooks in this file. Each hook passes the call on to every
 * family (shaderfilter, shadertastic, retro) and to our own filters.
 */
#include <obs-module.h>
#include <util/text-lookup.h>

#include "scf-family.h"

#define SCF_VERSION "0.1.0"

/* Same as OBS_DECLARE_MODULE(), but it also gives the pointer to every family. */
static obs_module_t *obs_module_pointer;

MODULE_EXPORT void obs_module_set_pointer(obs_module_t *module);
void obs_module_set_pointer(obs_module_t *module)
{
	obs_module_pointer = module;
	scf_shaderfilter_set_pointer(module);
	scf_shadertastic_set_pointer(module);
	scf_retro_set_pointer(module);
}

obs_module_t *obs_current_module(void)
{
	return obs_module_pointer;
}

MODULE_EXPORT uint32_t obs_module_ver(void);
uint32_t obs_module_ver(void)
{
	return LIBOBS_API_VER;
}

OBS_MODULE_AUTHOR("aaddrick")

/* Text for our own filters lives in data/locale/. */
static lookup_t *obs_module_lookup;

const char *obs_module_text(const char *val)
{
	const char *out = val;
	text_lookup_getstr(obs_module_lookup, val, &out);
	return out;
}

bool obs_module_get_string(const char *val, const char **out)
{
	return text_lookup_getstr(obs_module_lookup, val, out);
}

void obs_module_set_locale(const char *locale)
{
	if (obs_module_lookup)
		text_lookup_destroy(obs_module_lookup);
	obs_module_lookup = obs_module_load_locale(obs_current_module(), "en-US", locale);

	scf_shaderfilter_set_locale(locale);
	scf_shadertastic_set_locale(locale);
	scf_retro_set_locale(locale);
}

void obs_module_free_locale(void)
{
	text_lookup_destroy(obs_module_lookup);
	obs_module_lookup = NULL;

	scf_shaderfilter_free_locale();
	scf_shadertastic_free_locale();
	scf_retro_free_locale();
}

MODULE_EXPORT const char *obs_module_name(void)
{
	return obs_module_text("ModuleName");
}

MODULE_EXPORT const char *obs_module_description(void)
{
	return obs_module_text("ModuleDescription");
}

bool obs_module_load(void)
{
	blog(LOG_INFO, "[silly-cam-filters] loading version %s", SCF_VERSION);

	bool ok = true;
	ok = scf_shaderfilter_load() && ok;
	ok = scf_shadertastic_load() && ok;
	ok = scf_retro_load() && ok;
	scf_silly_register();

	if (!ok)
		blog(LOG_WARNING, "[silly-cam-filters] a filter family failed to load");
	return true;
}

void obs_module_post_load(void)
{
	scf_shaderfilter_post_load();
}

void obs_module_unload(void)
{
	scf_retro_unload();
	scf_shadertastic_unload();
	scf_shaderfilter_unload();

	scf_shaderfilter_free_data_path();
	scf_shadertastic_free_data_path();
	scf_retro_free_data_path();
}
