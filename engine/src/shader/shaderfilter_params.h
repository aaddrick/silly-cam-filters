/* Silly Cam Filters engine: settings for obs-shaderfilter shaders. GPL-2.0. */
#pragma once

#include <string>
#include <jansson.h>
#include <obs-module.h>

/* Builds a Shadertastic "parameters" array from the uniforms of a compiled shader. */
json_t *shaderfilter_build_parameters(gs_effect_t *effect, const std::string &shader_path);

/* True if a shader file is an obs-shaderfilter transition (uses image_a and image_b). */
bool shaderfilter_is_transition_source(const std::string &text);
