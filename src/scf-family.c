/*
 * silly-cam-filters: shim functions that give each filter family its own
 * folder under the module's data and config directories.
 */
#include "scf-family.h"

#include <util/bmem.h>
#include <util/dstr.h>
#include <util/platform.h>

static char *join(const char *subdir, const char *file)
{
	struct dstr path = {0};
	dstr_copy(&path, subdir);
	if (file && *file) {
		dstr_cat(&path, "/");
		dstr_cat(&path, file);
	} else {
		dstr_cat(&path, "/");
	}
	return path.array;
}

char *scf_find_file(obs_module_t *module, const char *subdir, const char *file)
{
	char *rel = join(subdir, file);
	char *out = obs_find_module_file(module, rel);
	bfree(rel);
	return out;
}

char *scf_config_path(obs_module_t *module, const char *subdir, const char *file)
{
	char *rel = join(subdir, file);
	char *out = obs_module_get_config_path(module, rel);
	bfree(rel);
	return out;
}

const char *scf_data_path(obs_module_t *module, const char *subdir, char **cache)
{
	if (!*cache) {
		struct dstr path = {0};
		dstr_copy(&path, obs_get_module_data_path(module));
		dstr_cat(&path, "/");
		dstr_cat(&path, subdir);
		*cache = path.array;
	}
	return *cache;
}

/* Same logic as obs_module_load_locale() in libobs, with a subfolder. */
lookup_t *scf_load_locale(obs_module_t *module, const char *subdir, const char *default_locale, const char *locale)
{
	struct dstr str = {0};
	lookup_t *lookup = NULL;
	char *file;

	dstr_printf(&str, "locale/%s.ini", default_locale);
	file = scf_find_file(module, subdir, str.array);
	if (file)
		lookup = text_lookup_create(file);
	bfree(file);

	if (!lookup) {
		blog(LOG_WARNING, "[silly-cam-filters] failed to load '%s' text for family '%s'", default_locale,
		     subdir);
		goto cleanup;
	}

	if (!locale || astrcmpi(locale, default_locale) == 0)
		goto cleanup;

	dstr_printf(&str, "locale/%s.ini", locale);
	file = scf_find_file(module, subdir, str.array);
	if (file && !text_lookup_add(lookup, file))
		blog(LOG_WARNING, "[silly-cam-filters] failed to load '%s' text for family '%s'", locale, subdir);
	bfree(file);

cleanup:
	dstr_free(&str);
	return lookup;
}

/* One shim per family. The subfolder names match the folders in data/. */
SCF_DEFINE_FAMILY_SHIM(engine, "engine")
