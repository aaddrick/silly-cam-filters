/*
 * silly-cam-filters: glue between the single OBS module and the
 * "families" of filters that came from separate upstream plugins.
 *
 * Each family is compiled with its OBS module hooks renamed
 * (see scf_add_family() in CMakeLists.txt). The effect engine is the one
 * family: its obs_module_load() is compiled as scf_engine_load(), and its
 * calls to obs_module_file("x") go to scf_engine_find_module_file(), which
 * looks in <data>/engine/x instead of <data>/x.
 *
 * This file declares the renamed hooks so that plugin.c can call them,
 * and the shim functions that send each family to its own data folder.
 */
#pragma once

#include <obs-module.h>
#include <util/text-lookup.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Shared shim helpers (scf-family.c). */
lookup_t *scf_load_locale(obs_module_t *module, const char *subdir, const char *default_locale, const char *locale);
char *scf_find_file(obs_module_t *module, const char *subdir, const char *file);
char *scf_config_path(obs_module_t *module, const char *subdir, const char *file);
const char *scf_data_path(obs_module_t *module, const char *subdir, char **cache);

/*
 * Declares the hooks that a family's renamed OBS_DECLARE_MODULE() and
 * OBS_MODULE_USE_DEFAULT_LOCALE() define, plus its renamed load/unload.
 */
#define SCF_DECLARE_FAMILY(F)                                  \
	void scf_##F##_set_pointer(obs_module_t *module);      \
	void scf_##F##_set_locale(const char *locale);         \
	void scf_##F##_free_locale(void);                      \
	bool scf_##F##_load(void);                             \
	void scf_##F##_unload(void);

/*
 * Defines the shim functions for one family. SUBDIR is the folder under
 * data/ that holds the family's files (locale/, shaders/, ...).
 */
#define SCF_DEFINE_FAMILY_SHIM(F, SUBDIR)                                                                 \
	static char *scf_##F##_data_path_cache;                                                           \
	lookup_t *scf_##F##_load_locale(obs_module_t *module, const char *default_locale, const char *locale) \
	{                                                                                                 \
		return scf_load_locale(module, SUBDIR, default_locale, locale);                           \
	}                                                                                                 \
	char *scf_##F##_find_module_file(obs_module_t *module, const char *file)                          \
	{                                                                                                 \
		return scf_find_file(module, SUBDIR, file);                                               \
	}                                                                                                 \
	char *scf_##F##_get_config_path(obs_module_t *module, const char *file)                           \
	{                                                                                                 \
		return scf_config_path(module, SUBDIR, file);                                             \
	}                                                                                                 \
	const char *scf_##F##_get_module_data_path(obs_module_t *module)                                  \
	{                                                                                                 \
		return scf_data_path(module, SUBDIR, &scf_##F##_data_path_cache);                         \
	}                                                                                                 \
	void scf_##F##_free_data_path(void)                                                               \
	{                                                                                                 \
		bfree(scf_##F##_data_path_cache);                                                         \
		scf_##F##_data_path_cache = NULL;                                                         \
	}

SCF_DECLARE_FAMILY(engine)

void scf_engine_free_data_path(void);

/* Our own filters (src/silly/). */
void scf_silly_register(void);

#ifdef __cplusplus
}
#endif
