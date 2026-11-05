/* Silly Cam Filters engine: built-in values, render passes and frame history. GPL-2.0. */
#pragma once

#include "effect.h"
#include "shader_filter.h"

struct effect_frame_params {
    int frame_index;
    float time;
    float delta_time;
    float rand_seed;
};

void engine_init_builtins(shadertastic_filter *s);
void engine_tick_builtins(shadertastic_filter *s, float seconds);
void engine_set_builtins(shadertastic_filter *s, effect_shader *sh, uint32_t cx, uint32_t cy);
bool engine_needs_history(effect_shader *sh, bool &prev_image, bool &prev_output);
void engine_copy_texture(gs_texture_t *src, gs_texrender_t **dst, uint32_t cx, uint32_t cy);
void engine_release_history(shadertastic_filter *s);

/* Renders all passes of an effect. Returns the texrender that holds the output, or nullptr. */
gs_texrender_t *engine_render_passes(shadertastic_filter *s, shadertastic_effect_t *e, uint32_t cx, uint32_t cy,
                                     const effect_frame_params &frame);
