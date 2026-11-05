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

#include <string>
#include <obs-module.h>
#include <jansson.h>
#include <util/platform.h>
#include "effect.h"
#include "logging_functions.hpp"
#include "try_gs_effect_set.h"
#include "parameters/parameter_facetracking.hpp"
#include "parameters/parameter_factory.h"
#include "parameters/parameter_prev_frame.hpp"
#include "shader/shaders_library.h"
#include "util/file_util.h"
#include "settings.h"
#include "shader/shaderfilter_params.h"

static gs_color_format parse_pass_format(const char *f) {
    if (f == nullptr) return GS_RGBA16;
    if (strcmp(f, "rgba16f") == 0) return GS_RGBA16F;
    if (strcmp(f, "rgba32f") == 0) return GS_RGBA32F;
    if (strcmp(f, "rgba") == 0) return GS_RGBA;
    return GS_RGBA16;
}

/* Silly Cam Filters engine: read "passes" from meta.json. */
static std::vector<effect_pass_def> parse_passes(json_t *metadata, const std::string &effect_name) {
    std::vector<effect_pass_def> out;
    json_t *passes = json_object_get(metadata, "passes");
    if (!json_is_array(passes)) {
        return out;
    }
    for (size_t i = 0; i < json_array_size(passes); i++) {
        json_t *p = json_array_get(passes, i);
        if (!json_is_object(p)) continue;
        effect_pass_def def;
        json_t *name = json_object_get(p, "name");
        if (!json_is_string(name)) {
            warn("Effect %s: pass %zu has no name; skipping it", effect_name.c_str(), i);
            continue;
        }
        def.name = json_string_value(name);
        json_t *tech = json_object_get(p, "technique");
        if (json_is_string(tech)) def.technique = json_string_value(tech);
        json_t *scale = json_object_get(p, "scale");
        if (json_is_number(scale)) def.scale = (float)json_number_value(scale);
        if (def.scale <= 0.0f) def.scale = 1.0f;
        json_t *iter = json_object_get(p, "iterations");
        if (json_is_integer(iter)) def.iterations = (int)json_integer_value(iter);
        else if (json_is_string(iter)) def.iterations_param = json_string_value(iter);
        json_t *fmt = json_object_get(p, "format");
        def.format = parse_pass_format(json_is_string(fmt) ? json_string_value(fmt) : nullptr);
        out.push_back(def);
    }
    return out;
}

static std::string file_stem(const std::string &path) {
    size_t slash = path.find_last_of("/\\");
    std::string base = slash == std::string::npos ? path : path.substr(slash + 1);
    size_t dot = base.find_last_of('.');
    return dot == std::string::npos ? base : base.substr(0, dot);
}

void shadertastic_effect_blueprint_t::load_blueprint() {
    dialect = shader_dialect_from_path(this->path);
    if (dialect != shader_dialect::shadertastic) {
        // Silly Cam Filters engine: an obs-shaderfilter file. The parameters
        // come from the compiled shader, in shadertastic_effect_t::load().
        label = file_stem(this->path);
        nb_steps = 1;
        metadata = json_object();
        json_object_set_new(metadata, "label", json_string(label.c_str()));
        json_object_set_new(metadata, "parameters", json_array());
        return;
    }
    std::string metadata_path = normalize_path(this->path + "/meta.json");
    debug(">>>>>>>>>>>>>>> load_effect %s %s %s", this->name.c_str(), this->path.c_str(), metadata_path.c_str());

    auto meta_json = load_file_zipped_or_local(metadata_path);

    if (!meta_json.has_value()) {
        // Something went wrong -> set default configuration
        warn("Unable to open file for effect %s.", name.c_str());
        label = name;
        nb_steps = 1;
        return;
    }

    json_error_t error;
    // For some obscure reason, we need to instanciate in a pointer THEN assign the pointer, a direct assign will SEGFAULT
    json_t *metadata_ = json_loads(meta_json.value().c_str(), 0, &error);
    metadata = metadata_;

    if (metadata == nullptr || !json_is_object(metadata)) {
        // Something went wrong -> set default configuration
        warn("Unable to parse metadata for effect %s. Check the JSON syntax", name.c_str());
        label = name;
        nb_steps = 1;

        //release_resource(json_decref, metadata);

        return;
    }
    else {
        std::string filters_dir = obs_module_file_std("effects");
        // Label
        json_t *label_json = json_object_get(metadata, "label");
        if (json_is_string(label_json)) {
            label = json_string_value(label_json);
            if (!starts_with(normalize_path(metadata_path), normalize_path(filters_dir))) {
                if (os_file_exists(metadata_path.c_str())) {
                    label = label + std::string(" 🔧");
                }
                else {
                    label = label + std::string(" 📦");
                }
            }
        }
        else {
            label = name;
        }

        // Silly Cam Filters engine: passes
        passes = parse_passes(metadata, name);

        // Steps
        json_t *steps_json = json_object_get(metadata, "steps");
        if (json_is_integer(steps_json)) {
            nb_steps = (int) json_integer_value(steps_json);
        }
        else {
            nb_steps = 1;
        }

        // Parameters
        json_t *parameters = json_object_get(metadata, "parameters");
        if (!json_is_array(parameters)) {
            warn("No parameters specified for effect %s", name.c_str());
            parameters = json_array();
        }

        // LEGACY - input_facedetection is deprecated.
        json_t *input_facedetection_json = json_object_get(metadata, "input_facedetection");
        legacy_input_facedetection =json_is_boolean(input_facedetection_json)
            ? json_boolean_value(input_facedetection_json)
            : false;
        if (legacy_input_facedetection) {
            json_t *param = json_pack(
                "{s:s,s:s}",
                "name", "fd",
                "type", "facetracking");
            json_array_insert_new(parameters, 0, param);
        }

        // LEGACY - input_time is deprecated.
        json_t *input_time_json = json_object_get(metadata, "input_time");
        legacy_input_time = json_is_boolean(input_time_json)
            ? json_boolean_value(input_time_json)
            : false;
        if (legacy_input_time) {
            json_t *param = json_pack(
                "{s:s,s:s,s:s}",
                "name", "time",
                "type", "time",
                "reset_on_show", "prompt"
            );
            json_array_insert_new(parameters, 0, param);
        }
        debug("Loaded Blueprint effect %s from %s", name.c_str(), metadata_path.c_str());
    }
}
void shadertastic_effect_t::load() {
    //load_blueprint();
    if (metadata == nullptr || !json_is_object(metadata)) {
        return;
    }

    json_incref(metadata);

    // Silly Cam Filters engine: obs-shaderfilter files get their parameters
    // from the uniforms of the compiled shader.
    if (dialect != shader_dialect::shadertastic) {
        this->main_shader = shaders_library.get(this->path);
        if (this->main_shader != nullptr && this->main_shader->get_gs_effect() != nullptr) {
            json_object_set_new(metadata, "parameters",
                shaderfilter_build_parameters(this->main_shader->get_gs_effect(), this->path));
        }
    }

    // Parameters
    json_t *parameters = json_object_get(metadata, "parameters");
    if (!json_is_array(parameters)) {
        warn("No parameters specified for effect %s", name.c_str());
        parameters = json_array();
    }

    if (parameters != nullptr && json_is_array(parameters)) {
        this->main_shader = shaders_library.get(this->path);
        this->param_facetracking = nullptr; // Resets the face_tracking param to null if present; no need to release, it's a weak pointer

        // Clear referenced parameters
        referenced_params.clear();

        // Copy the effect params map to allow recycling
        params_list previous_effect_params(effect_params);
        effect_params.clear();

        prev_frames_to_keep.resize(nb_steps);
        std::fill(prev_frames_to_keep.begin(), prev_frames_to_keep.end(), nullptr);

        // Load parameters
        //debug("%s", json_dumps(parameters, 0));
        size_t nb_parameters = json_array_size(parameters);
        for (size_t i=0; i < nb_parameters; i++) {
            json_t *param_metadata = json_array_get(parameters, i);
            if (!json_is_object(param_metadata)) {
                continue;
            }
            effect_parameter *effect_param = effect_parameter_factory::create(name, this->path, main_shader.get(), param_metadata);

            if (effect_param != nullptr) {
                auto param_type = effect_param->type();
                if (param_type == PARAM_DATATYPE_PREV_FRAME) {
                    auto *effect_param_prev_frame = dynamic_cast<effect_parameter_prev_frame *>(effect_param);

                    int step_to_keep = effect_param_prev_frame->step();
                    if (step_to_keep < 0) {
                        step_to_keep = nb_steps - 1;
                    }
                    if (step_to_keep >= nb_steps) {
                        log_error("Trying to use a prev frame on a step higher than the maximum steps : %s\n", name.c_str());
                    }
                    else {
                        prev_frames_to_keep[step_to_keep] = effect_param_prev_frame;
                    }
                }
                else if (param_type == PARAM_DATATYPE_FACETRACKING) {
                    if (param_facetracking != nullptr) {
                        log_error(
                            "Trying to use multiple face tracking parameters. This makes no sense. Params: %s and %s",
                            effect_param->get_name().c_str(),
                            param_facetracking->get_name().c_str()
                        );
                    }
                    else {
                        param_facetracking = effect_param;
                    }
                }

                std::string param_name_str;
                json_t *name_json = json_object_get(param_metadata, "name");
                if (json_is_string(name_json)) {
                    param_name_str = json_string_value(name_json);
                }
                effect_parameter *previous_param = previous_effect_params.get(param_name_str);
                if (previous_param != nullptr) {
                    if (previous_param->get_data_size() == effect_param->get_data_size()) {
                        debug(
                            "Recycling data for %s (size: %i)",
                            param_name_str.c_str(),
                            (int)effect_param->get_data_size()
                        );
                        memcpy(effect_param->get_data(), previous_param->get_data(), effect_param->get_data_size());
                    }
                }

                effect_params.put(param_name_str, effect_param);

                effect_param->prepare_conditions(referenced_params);
            }
        }

        // Clear memory of removed params
        for (auto param: previous_effect_params) {
            debug ("Free removed param %s", param->get_name().c_str());
            delete param;
        }

        //debug("Loaded effect %s from %s", name.c_str(), metadata_path.c_str());
    }
    loaded = (this->main_shader != nullptr);
}

void shadertastic_effect_t::reload() {
    shaders_library.reload(this->path);
    load_blueprint();
    load();
}

void shadertastic_effect_t::create_properties(obs_properties *props) {
    const char *effect_label = label.c_str();
    obs_properties_t *effect_group = obs_properties_create();

    obs_properties_t *warning_group = obs_properties_create();
    std::string warning_group_name = (name + "__warning");
    auto *warning_group_prop = obs_properties_add_group(props, warning_group_name.c_str(), "⚠ Shader error", OBS_GROUP_NORMAL, warning_group);
    obs_property_set_visible(warning_group_prop, false);
    auto prop = obs_properties_add_text(
        warning_group,
        (name + "__compile_error").c_str(),
        error_str().c_str(),
        OBS_TEXT_INFO
    );
    obs_property_text_set_info_type(prop, OBS_TEXT_INFO_WARNING);

    for (auto param: effect_params) {
        if (!param->is_dev_mode() || shadertastic_settings().dev_mode_enabled) {
            param->render_property_ui(name.c_str(), effect_group);
        }
    }
    obs_properties_add_group(props, (name + "__params").c_str(), effect_label, OBS_GROUP_NORMAL, effect_group);
    obs_property_set_visible(obs_properties_get(props, (name + "__params").c_str()), false);
}

void shadertastic_effect_t::attach_listeners(obs_properties *props) {
    for (auto &[referenced_param_name, listeners_list] : referenced_params) {
        auto *prop = obs_properties_get(props, referenced_param_name.c_str());
        obs_property_set_modified_callback2(prop, [](void *data, obs_properties_t *props, obs_property_t *property, obs_data_t *settings) {
            std::string prop_name = obs_property_name(property);
            if (prop_name.find('.') == std::string::npos) {
                // Should not happen, but stop if it happens for any reason
                warn("An observed property has no base effet: '%s'. This is normally impossible.", prop_name.c_str());
                return false;
            }
            std::string effect_name = prop_name.substr(0, prop_name.find('.'));
            auto *self = static_cast<shadertastic_effect_t *>(data);
            auto &listeners = self->referenced_params[prop_name];
            bool changed = false;
            for (auto *listener : listeners) {
                if (listener != nullptr) {
                    bool should_be_visible = listener->condition_check(settings);
                    bool currently_visible = listener->is_visible();
                    listener->set_visible(should_be_visible);
                    listener->apply_visible(effect_name.c_str(), props, should_be_visible);
                    changed |= (should_be_visible != currently_visible);
                }
            }
            return changed;
        }, (void *) this);
    }
}

void shadertastic_effect_t::set_params(
    gs_texture_t *a, gs_texture_t *b,
    int frame_index, bool is_studio_mode,
    float t, float delta_t,
    uint32_t cx, uint32_t cy,
    float rand_seed) {
    /* texture setters look reversed, but they aren't */
    if (gs_get_color_space() == GS_CS_SRGB) {
        /* users want nonlinear effect */
        try_gs_effect_set_texture("tex_a", main_shader->param_tex_a, a);
        try_gs_effect_set_texture("tex_b", main_shader->param_tex_b, b);
    }
    else {
        /* nonlinear effect is too wrong, so use linear effect */
        try_gs_effect_set_texture_srgb("tex_a", main_shader->param_tex_a, a);
        try_gs_effect_set_texture_srgb("tex_b", main_shader->param_tex_b, b);
    }
    //debug("input textures set");

    try_gs_effect_set_bool("is_studio_mode", main_shader->param_is_studio_mode, is_studio_mode);
    try_gs_effect_set_int("frame_index", main_shader->param_frame_index, frame_index);
    try_gs_effect_set_float("time", main_shader->param_time, t);
    try_gs_effect_set_float("delta_time", main_shader->param_delta_time, delta_t);
    try_gs_effect_set_float("upixel", main_shader->param_upixel, (float)(1.0/cx));
    try_gs_effect_set_float("vpixel", main_shader->param_vpixel, (float)(1.0/cy));
    try_gs_effect_set_float("rand_seed", main_shader->param_rand_seed, rand_seed);
    try_gs_effect_set_int("nb_steps", main_shader->param_nb_steps, nb_steps);
    //debug("common params set");

    for (auto param: effect_params) {
        param->try_gs_set_val();
    }
    //debug("all params set");
}

void shadertastic_effect_t::set_step_params(int current_step, gs_texture_t *interm) const {
    if (gs_get_color_space() == GS_CS_SRGB) {
        /* users want nonlinear fade */
        try_gs_effect_set_texture("tex_interm", main_shader->param_tex_interm, interm);
    }
    else {
        /* nonlinear fade is too wrong, so use linear fade */
        try_gs_effect_set_texture_srgb("tex_interm", main_shader->param_tex_interm, interm);
    }
    try_gs_effect_set_int("current_step", main_shader->param_current_step, current_step);
}

void shadertastic_effect_t::show() {
    debug("show %s", this->name.c_str());
    for (auto param: this->effect_params) {
        if (param != nullptr) {
            param->show();
        }
    }
}

void shadertastic_effect_t::hide() {
    debug("hide %s", this->name.c_str());
    for (auto param: this->effect_params) {
        if (param != nullptr) {
            param->hide();
        }
    }
}

int shadertastic_effect_t::pass_iterations(const size_t pass_idx) const {
    const effect_pass_def &def = passes[pass_idx];
    int n = def.iterations;
    if (!def.iterations_param.empty()) {
        effect_parameter *param = const_cast<params_list &>(effect_params).get(def.iterations_param);
        if (param != nullptr && param->get_data() != nullptr) {
            if (param->type() == PARAM_DATATYPE_DOUBLE) n = (int)*(float *)param->get_data();
            else n = *(int *)param->get_data();
        }
    }
    return n < 1 ? 1 : (n > 64 ? 64 : n);
}

void shadertastic_effect_t::release_gpu() {
    obs_enter_graphics();
    for (auto &rt : pass_runtime) {
        release_resource(gs_texrender_destroy, rt.buf[0]);
        release_resource(gs_texrender_destroy, rt.buf[1]);
        release_resource(gs_texrender_destroy, rt.prev);
    }
    obs_leave_graphics();
    pass_runtime.clear();
}

void shadertastic_effect_t::release() {
    release_gpu();
    for (auto effect_param: effect_params) {
        delete effect_param;
    }
    effect_params.clear();
}
