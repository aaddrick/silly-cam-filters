/* Silly Cam Filters engine: settings conversion for old filter IDs. GPL-2.0. */
#pragma once

#include <obs-module.h>

#define LEGACY_SHADER_FILTER_ID "shader_filter"
#define LEGACY_RETRO_FILTER_ID "obs_retro_effects_filter"

/* Converts obs-shaderfilter or obs-retro-effects settings to the engine format, once. */
void engine_convert_legacy_settings(const char *source_id, obs_data_t *settings);
