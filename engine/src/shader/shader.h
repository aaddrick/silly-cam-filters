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

#ifndef SHADERTASTIC_SHADER_H
#define SHADERTASTIC_SHADER_H

#include <string>
#include <unordered_map>
#include <obs-module.h>

/**
 * Silly Cam Filters engine: the source format of a shader.
 * - shadertastic:       main.hlsl in an effect folder, with the Shadertastic header
 * - shaderfilter_shader: an obs-shaderfilter .shader file, wrapped in its template
 * - shaderfilter_effect: an obs-shaderfilter .effect file, used as it is
 */
enum class shader_dialect { shadertastic, shaderfilter_shader, shaderfilter_effect };

shader_dialect shader_dialect_from_path(const std::string &path);

class effect_shader {
    private:
    gs_effect_t *gs_effect = nullptr;
    std::unordered_map<std::string, gs_eparam_t *> param_cache;
    gs_vertbuffer_t *sprite_buffer = nullptr; // a quad in pixel units (see render())

    public:
    // 0 -> 1 with transitions; time elapsed with filters when enabled
    gs_eparam_t *param_time = nullptr;

    // Filter only
    gs_eparam_t *param_image = nullptr;

    // Transition only
    gs_eparam_t *param_tex_a = nullptr;
    gs_eparam_t *param_tex_b = nullptr;
    gs_eparam_t *param_is_studio_mode = nullptr;

    // Transition and filter
    gs_eparam_t *param_tex_interm = nullptr;
    gs_eparam_t *param_frame_index = nullptr;
    gs_eparam_t *param_delta_time = nullptr;
    gs_eparam_t *param_upixel = nullptr;
    gs_eparam_t *param_vpixel = nullptr;
    gs_eparam_t *param_rand_seed = nullptr;
    gs_eparam_t *param_current_step = nullptr;
    gs_eparam_t *param_nb_steps = nullptr;

    std::string path{};
    shader_dialect dialect = shader_dialect::shadertastic;

    ~effect_shader();

    [[nodiscard]] inline gs_effect_t *get_gs_effect() const { return gs_effect; }

    /* Built-in uniforms: set a value only if the shader declares the uniform. */
    gs_eparam_t *find_param(const char *name);
    void set_float_if(const char *name, float v);
    void set_int_if(const char *name, int v);
    void set_bool_if(const char *name, bool v);
    void set_vec2_if(const char *name, float x, float y);
    void set_vec3_if(const char *name, float x, float y, float z);
    void set_texture_if(const char *name, gs_texture_t *tex, bool srgb);
    bool has_param(const char *name) { return find_param(name) != nullptr; }

    std::string load(const char *shader_path);

    [[nodiscard]] inline gs_eparam_t * get_param_by_name(const char *param_name) const { return param_name == nullptr ? nullptr : gs_effect_get_param_by_name(gs_effect, param_name); }
    [[nodiscard]] inline gs_eparam_t * get_param_by_name(const std::string &param_name) const { return get_param_by_name(param_name.c_str()); }
    [[nodiscard]] inline gs_technique_t * get_technique(const char *tech_name) const { return tech_name == nullptr ? nullptr : gs_effect_get_technique(gs_effect, tech_name); }
    [[nodiscard]] inline gs_technique_t * get_technique(const std::string &tech_name) const { return get_technique(tech_name.c_str()); }

    void render(const gs_texrender_t *texrender, const char *tech_name, uint32_t cx, uint32_t cy);

    void release();

    //See cpp file for details
    //private:
    //static bool sourceHasValidBraces(const std::string& str);
    //static std::string removeComments(const std::string& str);
};

#endif // SHADERTASTIC_SHADER_H
