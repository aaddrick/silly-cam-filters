/******************************************************************************
    Copyright (C) 2023 by xurei <xureilab@gmail.com>

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <http://www.gnu.org/licenses/>.
******************************************************************************/

#include <obs-module.h>
#include <string>
#include "../logging_functions.hpp"
#include "../util/file_util.h"
#include "../is_module_loaded.h"
#include "shader.h"
#include "../shadertastic.hpp"
#include "src/util/hlsl_expander.hpp"
#include "src/settings.h"
#include "shaderfilter_template.h"
#include "src/util/string_util.h"

shader_dialect shader_dialect_from_path(const std::string &path) {
    if (ends_with(path, ".shader")) {
        return shader_dialect::shaderfilter_shader;
    }
    if (ends_with(path, ".effect")) {
        return shader_dialect::shaderfilter_effect;
    }
    return shader_dialect::shadertastic;
}

static void replace_all(std::string &s, const std::string &from, const std::string &to) {
    if (from.empty()) {
        return;
    }
    size_t pos = 0;
    while ((pos = s.find(from, pos)) != std::string::npos) {
        s.replace(pos, from.length(), to);
        pos += to.length();
    }
}

/* Same preparation as obs-shaderfilter's shader_filter_reload_effect(). */
static std::string wrap_shaderfilter_source(const std::string &text, const bool use_template) {
    std::string out;
    if (use_template) {
        out += sf_effect_template_begin;
    }
    out += text;
    if (use_template) {
        out += sf_effect_template_end;
    }
    if (gs_get_device_type() == GS_DEVICE_OPENGL) {
        replace_all(out, "[loop]", "");
        out.insert(0, "#define OPENGL 1\n");
    }
    return out;
}

effect_shader::~effect_shader() {
    //debug("DELETE effect_shader %s", path.c_str());
    this->release();
}

std::string effect_shader::load(const char *shader_path) {
    debug("SHADER PATH: %s", shader_path);
    this->path = std::string(shader_path);
    char *error_string = nullptr;
    auto shader_source_ = load_file_zipped_or_local(shader_path);
    if (!shader_source_.has_value()) {
        log_error("Could not open shader file %s : File does not exist", shader_path);
        return "File does not exist";
    }
    else {
        dialect = shader_dialect_from_path(this->path);
        std::string shader_source;
        if (dialect != shader_dialect::shadertastic) {
            obs_enter_graphics();
            shader_source = wrap_shaderfilter_source(shader_source_.value(), dialect == shader_dialect::shaderfilter_shader);
            obs_leave_graphics();
        }
        else {
        // Global common arguments, must be in all the effects for this plugin
        shader_source = (std::string("") +
            "uniform float4x4 ViewProj;\n" +
            "uniform texture2d image;\n" +
            "uniform texture2d tex_a;\n" +
            "uniform texture2d tex_b;\n" +
            "uniform texture2d tex_interm;\n"
            "uniform int frame_index;\n" +
            "uniform float time;\n" +
            "uniform bool is_studio_mode;\n" +
            "uniform float delta_time;\n" +
            "uniform float upixel;\n" +
            "uniform float vpixel;\n" +
            "uniform float rand_seed;\n" +
            "uniform int current_step;\n" +
            "uniform int nb_steps;\n" +
            "float srgb_nonlinear_to_linear_channel(float u) { return (u <= 0.04045) ? (u / 12.92) : pow((u + 0.055) / 1.055, 2.4); }\n" +
            "float3 srgb_nonlinear_to_linear(float3 v) { return float3(srgb_nonlinear_to_linear_channel(v.r), srgb_nonlinear_to_linear_channel(v.g), srgb_nonlinear_to_linear_channel(v.b)); }\n" +
            "float srgb_linear_to_nonlinear_channel(float u) { return (u <= 0.0031308) ? (12.92 * u) : ((1.055 * pow(u, 1. / 2.4)) - 0.055); }\n" +
            "float3 srgb_linear_to_nonlinear(float3 v) { return float3(srgb_linear_to_nonlinear_channel(v.r), srgb_linear_to_nonlinear_channel(v.g), srgb_linear_to_nonlinear_channel(v.b)); }\n" +
            "#ifdef _D3D11 \n #define fract(a) frac(a) \n #else \n #define frac(a) fract(a) \n #endif \n" +
            "sampler_state facetracking_sampler { Filter=Point; AddressU=Clamp; AddressV=Clamp;}; \n" +
            "#define facetracking_edge(fd_points_tex, edge_idx) fd_points_tex.Sample(facetracking_sampler, float2(((edge_idx) + 0.5)/478.0, 0.0)).xyz \n" +
            "#define facetracking_tex_edge(fd_points_tex, edge_idx) fd_points_tex.Sample(facetracking_sampler, float2(((edge_idx) + 0.5)/478.0, 1.0)).xyz \n" +
            shader_source_.value()
        );
        }
        try {
            HLSLExpander expander;
            if (!shadertastic_settings().library_path.empty()) {
                expander.addPath(shadertastic_settings().library_path);
            }
            fs::path fs_path(shader_path);
            shader_source = expander.expand_includes(shader_source, fs_path.parent_path().c_str(), load_file_local);
        }
        catch (std::runtime_error &e) {
            log_error("Could not parse shader file %s :\n%s", shader_path, e.what());
            return e.what();
        }

        obs_enter_graphics();
        gs_effect = gs_effect_create(shader_source.c_str(), shader_path, (char**)&error_string);
        obs_leave_graphics();

        if (!gs_effect) {
            log_error("Could not open shader file %s :\n%s", shader_path, error_string);
            std::string error_str = std::string("") + error_string;
            bfree(error_string);
            return error_str;
        }
        else {
            param_image = gs_effect_get_param_by_name(gs_effect, "image");
            param_tex_a = gs_effect_get_param_by_name(gs_effect, "tex_a");
            param_tex_b = gs_effect_get_param_by_name(gs_effect, "tex_b");
            param_is_studio_mode = gs_effect_get_param_by_name(gs_effect, "is_studio_mode");
            param_tex_interm = gs_effect_get_param_by_name(gs_effect, "tex_interm");
            param_frame_index = gs_effect_get_param_by_name(gs_effect, "frame_index");
            param_time = gs_effect_get_param_by_name(gs_effect, "time");
            param_delta_time = gs_effect_get_param_by_name(gs_effect, "delta_time");
            param_upixel = gs_effect_get_param_by_name(gs_effect, "upixel");
            param_vpixel = gs_effect_get_param_by_name(gs_effect, "vpixel");
            param_rand_seed = gs_effect_get_param_by_name(gs_effect, "rand_seed");
            param_current_step = gs_effect_get_param_by_name(gs_effect, "current_step");
            param_nb_steps = gs_effect_get_param_by_name(gs_effect, "nb_steps");

            return "";
        }
    }
}

void effect_shader::render(const gs_texrender_t *texrender, const char *tech_name, const uint32_t cx, const uint32_t cy) {
    auto *tech = get_technique(tech_name);
    auto *texture = texrender != nullptr ? gs_texrender_get_texture(texrender) : nullptr;

    const size_t passes = gs_technique_begin(tech);
    for (size_t i = 0; i < passes; i++) {
        gs_technique_begin_pass(tech, i);
        gs_draw_sprite(texture, 0, cx, cy);
        gs_technique_end_pass(tech);
    }
    gs_technique_end(tech);
}

gs_eparam_t *effect_shader::find_param(const char *name) {
    if (gs_effect == nullptr) {
        return nullptr;
    }
    auto it = param_cache.find(name);
    if (it != param_cache.end()) {
        return it->second;
    }
    gs_eparam_t *p = gs_effect_get_param_by_name(gs_effect, name);
    param_cache.emplace(name, p);
    return p;
}

void effect_shader::set_float_if(const char *name, const float v) {
    if (auto *p = find_param(name)) gs_effect_set_float(p, v);
}
void effect_shader::set_int_if(const char *name, const int v) {
    if (auto *p = find_param(name)) gs_effect_set_int(p, v);
}
void effect_shader::set_bool_if(const char *name, const bool v) {
    if (auto *p = find_param(name)) gs_effect_set_bool(p, v);
}
void effect_shader::set_vec2_if(const char *name, const float x, const float y) {
    if (auto *p = find_param(name)) {
        vec2 v{};
        vec2_set(&v, x, y);
        gs_effect_set_vec2(p, &v);
    }
}
void effect_shader::set_vec3_if(const char *name, const float x, const float y, const float z) {
    if (auto *p = find_param(name)) {
        vec3 v{};
        vec3_set(&v, x, y, z);
        gs_effect_set_vec3(p, &v);
    }
}
void effect_shader::set_texture_if(const char *name, gs_texture_t *tex, const bool srgb) {
    if (auto *p = find_param(name)) {
        if (srgb) gs_effect_set_texture_srgb(p, tex);
        else gs_effect_set_texture(p, tex);
    }
}

void effect_shader::release() {
    param_cache.clear();
    if (is_module_loaded() && gs_effect != nullptr) {
        debug("Release shader");
        obs_enter_graphics();
        {
            release_resource(gs_effect_destroy, gs_effect);
        }
        obs_leave_graphics();
    }
}

// These were an attempt to check the syntax of the shader, and avoid crashes during effect development
// But it is too simple and creates other weird problems (e.g. /* //bla */)
//bool effect_shader::sourceHasValidBraces(const std::string& str) {
//    int counter = 0;
//
//    for (char ch : str) {
//        if (ch == '{') {
//            counter++;
//        }
//        else if (ch == '}') {
//            counter--;
//            // If counter goes negative, there's a mismatched closing brace
//            if (counter < 0) {
//                log_error("COUNTER IS NEGATIVE");
//                return false;
//            }
//        }
//    }
//
//    if (counter != 0) {
//        log_error("COUNTER IS NOT ZERO");
//    }
//
//    // The string is valid if the counter is zero at the end
//    return counter == 0;
//}
//
//std::string effect_shader::removeComments(const std::string& code) {
//    // Regular expression to match single-line and multi-line comments
//    std::regex singleLineComment(R"(//.*?$)", std::regex_constants::multiline);
//    std::regex multiLineComment(R"(/\*.*?\*/)");
//
//    // Create a copy of the input code to modify
//    std::string result = code;
//
//    // Remove single-line comments
//    result = std::regex_replace(result, singleLineComment, "");
//
//    // Remove multi-line comments while preserving new lines
//    std::sregex_iterator it(result.begin(), result.end(), multiLineComment);
//    std::sregex_iterator end;
//    for (; it != end; ++it) {
//        std::string match = it->str();
//        size_t newlineCount = std::count(match.begin(), match.end(), '\n');
//        result.replace(it->position(), match.length(), std::string(newlineCount, '\n'));
//    }
//
//    return result;
//}
