/******************************************************************************
    Silly Cam Filters engine: built-in values, render passes and frame history.
    See docs/ENGINE.md.

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 2 of the License, or
    (at your option) any later version.
******************************************************************************/

#include <cmath>
#include <cstdlib>
#include <obs-module.h>
#include <util/platform.h>
#include "engine_render.h"
#include "obs-source-custom.h"
#include "util/texture_util.h"
#include "util/resource_util.hpp"

extern gs_texture_t *shadertastic_transparent_texture;

static float random01() {
    return (float)rand() / (float)RAND_MAX; // NOLINT(*-msc50-cpp)
}

void engine_init_builtins(shadertastic_filter *s) {
    s->rand_instance_f = random01();
    s->rand_activation_f = random01();
    s->rand_f = random01();
}

void engine_tick_builtins(shadertastic_filter *s, const float seconds) {
    s->elapsed_time += seconds;
    s->loop_second += seconds;
    if (s->loop_second > 1.0f) {
        s->loop_second -= 1.0f;
        s->loops += 1;
        if (s->loops >= 4194304) s->loops = -s->loops;
    }

    const bool enabled = s->source != nullptr && obs_source_enabled(s->source);
    if (enabled != s->engine_enabled) {
        s->engine_enabled = enabled;
        if (enabled) {
            s->enable_time = s->elapsed_time;
            s->rand_activation_f = random01();
        }
    }
    obs_source_t *parent = s->source != nullptr ? obs_filter_get_parent(s->source) : nullptr;
    s->active_time = (enabled && parent && obs_source_active(parent)) ? s->active_time + seconds : 0.0f;
    s->show_time = (enabled && parent && obs_source_showing(parent)) ? s->show_time + seconds : 0.0f;
    s->rand_f = random01();
}

static bool texture_srgb() {
    // Same rule as Shadertastic for its own textures.
    return gs_get_color_space() != GS_CS_SRGB;
}

void engine_set_builtins(shadertastic_filter *s, effect_shader *sh, const uint32_t cx, const uint32_t cy) {
    const auto w = (float)cx, h = (float)cy;
    // obs-shaderfilter values
    sh->set_vec2_if("uv_offset", 0.0f, 0.0f);
    sh->set_vec2_if("uv_scale", 1.0f, 1.0f);
    sh->set_vec2_if("uv_pixel_interval", 1.0f / w, 1.0f / h);
    sh->set_vec2_if("uv_size", w, h);
    sh->set_float_if("elapsed_time", s->elapsed_time);
    sh->set_float_if("elapsed_time_start", s->elapsed_time - s->effect_start_time);
    sh->set_float_if("elapsed_time_show", s->show_time);
    sh->set_float_if("elapsed_time_active", s->active_time);
    sh->set_float_if("elapsed_time_enable", s->elapsed_time - s->enable_time);
    sh->set_int_if("loops", s->loops);
    sh->set_float_if("loop_second", s->loop_second);
    sh->set_float_if("local_time", (float)(os_gettime_ns() / 1000000000.0));
    sh->set_float_if("rand_f", s->rand_f);
    sh->set_float_if("rand_instance_f", s->rand_instance_f);
    sh->set_float_if("rand_activation_f", s->rand_activation_f);
    // Shadertoy names
    sh->set_float_if("iTime", s->time);
    sh->set_float_if("iTimeDelta", s->delta_time);
    sh->set_float_if("iFrame", (float)s->frame_index);
    sh->set_vec3_if("iResolution", w, h, 1.0f);
    // History
    const bool srgb = texture_srgb();
    {
        gs_texture_t *t = s->prev_image_texrender != nullptr ? gs_texrender_get_texture(s->prev_image_texrender) : shadertastic_transparent_texture;
        sh->set_texture_if("previous_image", t, srgb);
        sh->set_texture_if("image_prev", t, srgb);
    }
    sh->set_texture_if("previous_output", s->prev_output_texrender != nullptr ? gs_texrender_get_texture(s->prev_output_texrender) : shadertastic_transparent_texture, srgb);
}

bool engine_needs_history(effect_shader *sh, bool &prev_image, bool &prev_output) {
    prev_image = sh->has_param("previous_image") || sh->has_param("image_prev");
    prev_output = sh->has_param("previous_output");
    return prev_image || prev_output;
}

void engine_copy_texture(gs_texture_t *src, gs_texrender_t **dst, const uint32_t cx, const uint32_t cy, const gs_color_format format) {
    if (src == nullptr) {
        return;
    }
    if (*dst != nullptr && gs_texrender_get_format(*dst) != format) {
        gs_texrender_destroy(*dst);
        *dst = nullptr;
    }
    if (*dst == nullptr) {
        *dst = gs_texrender_create(format, GS_ZS_NONE);
    }
    gs_texrender_reset(*dst);
    if (gs_texrender_begin_with_color_space(*dst, cx, cy, GS_CS_SRGB_16F)) {
        constexpr vec4 clear_color{0, 0, 0, 0};
        gs_clear(GS_CLEAR_COLOR, &clear_color, 0.0f, 0);
        gs_ortho(0.0f, (float)cx, 0.0f, (float)cy, -100.0f, 100.0f);
        render_texture(src, true, false);
        gs_texrender_end(*dst);
    }
}

void engine_release_history(shadertastic_filter *s) {
    obs_enter_graphics();
    release_resource(gs_texrender_destroy, s->prev_image_texrender);
    release_resource(gs_texrender_destroy, s->prev_output_texrender);
    obs_leave_graphics();
}

/* Float buffers are never sRGB-encoded on write, so they must not be decoded on read. */
static bool is_float_format(const gs_color_format f) {
    return f == GS_RGBA16F || f == GS_RGBA32F || f == GS_R16F || f == GS_R32F || f == GS_RG16F || f == GS_RG32F;
}

static gs_texrender_t *ensure_texrender(gs_texrender_t *&tr, const gs_color_format format) {
    if (tr != nullptr && gs_texrender_get_format(tr) != format) {
        gs_texrender_destroy(tr);
        tr = nullptr;
    }
    if (tr == nullptr) {
        tr = gs_texrender_create(format, GS_ZS_NONE);
    }
    return tr;
}

gs_texrender_t *engine_render_passes(shadertastic_filter *s, shadertastic_effect_t *e, const uint32_t cx, const uint32_t cy,
                                     const effect_frame_params &frame) {
    effect_shader *sh = e->main_shader.get();
    const size_t n = e->passes.size();
    if (e->pass_runtime.size() != n) {
        e->release_gpu();
        e->pass_runtime.resize(n);
    }

    // A pass keeps last frame's output only if some shader asks for <pass>_prev.
    for (size_t i = 0; i < n; i++) {
        e->pass_runtime[i].keep_prev = sh->has_param((e->passes[i].name + "_prev").c_str());
    }

    constexpr vec4 clear_color{0, 0, 0, 0};

    for (size_t i = 0; i < n; i++) {
        const effect_pass_def &def = e->passes[i];
        effect_pass_runtime &rt = e->pass_runtime[i];
        const uint32_t w = def.width > 0 ? (uint32_t)def.width : std::max<uint32_t>(1, (uint32_t)std::lround(cx * def.scale));
        const uint32_t h = def.height > 0 ? (uint32_t)def.height : std::max<uint32_t>(1, (uint32_t)std::lround(cy * def.scale));
        rt.width = w;
        rt.height = h;
        ensure_texrender(rt.buf[0], def.format);
        ensure_texrender(rt.buf[1], def.format);

        const int iterations = e->pass_iterations(i);
        for (int it = 0; it < iterations; it++) {
            gs_texrender_t *target = rt.buf[rt.cur ^ 1];
            gs_texrender_reset(target);
            if (!gs_texrender_begin_with_color_space(target, w, h, GS_CS_SRGB_16F)) {
                return nullptr;
            }
            gs_clear(GS_CLEAR_COLOR, &clear_color, 0.0f, 0);
            gs_ortho(0.0f, (float)w, 0.0f, (float)h, -100.0f, 100.0f);
            // Decide inside the render target, as Shadertastic does for its steps.
            const bool srgb = texture_srgb();

            // Textures must be bound again for each draw.
            e->set_step_params((int)i, nullptr);
            e->set_params(nullptr, nullptr, frame.frame_index, false, frame.time, frame.delta_time, cx, cy, frame.rand_seed);
            engine_set_builtins(s, sh, cx, cy);

            for (size_t j = 0; j < n; j++) {
                const effect_pass_runtime &other = e->pass_runtime[j];
                const bool pass_srgb = srgb && !is_float_format(e->passes[j].format);
                if (j <= i && other.buf[other.cur] != nullptr) {
                    // Earlier passes: this frame's output. This pass: the previous iteration (or frame).
                    gs_texture_t *t = gs_texrender_get_texture(other.buf[other.cur]);
                    sh->set_texture_if(e->passes[j].name.c_str(), t != nullptr ? t : shadertastic_transparent_texture, pass_srgb);
                }
                if (other.keep_prev) {
                    // Before the first frame is kept, the shader sees a transparent texture.
                    gs_texture_t *prev_tex = other.prev != nullptr ? gs_texrender_get_texture(other.prev) : shadertastic_transparent_texture;
                    sh->set_texture_if((e->passes[j].name + "_prev").c_str(), prev_tex, pass_srgb);
                }
            }
            sh->set_int_if("pass_index", (int)i);
            sh->set_vec2_if("pass_size", (float)w, (float)h);
            sh->set_vec2_if("pass_texel", 1.0f / (float)w, 1.0f / (float)h);
            sh->set_int_if("iteration", it);
            sh->set_int_if("iterations", iterations);

            shadertastic_source_process_filter_tech_end(s->source, s->filter_texrender, sh, w, h, def.technique.c_str());
            gs_texrender_end(target);
            rt.cur ^= 1;
        }
    }

    // Keep the outputs that a shader reads as <pass>_prev in the next frame.
    for (size_t i = 0; i < n; i++) {
        effect_pass_runtime &rt = e->pass_runtime[i];
        if (rt.keep_prev) {
            engine_copy_texture(gs_texrender_get_texture(rt.buf[rt.cur]), &rt.prev, rt.width, rt.height, e->passes[i].format);
        }
    }

    effect_pass_runtime &last = e->pass_runtime[n - 1];
    return last.buf[last.cur];
}
