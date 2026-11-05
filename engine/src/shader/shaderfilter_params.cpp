/******************************************************************************
    Silly Cam Filters engine: build Shadertastic-style parameters from the
    uniforms of an obs-shaderfilter shader.

    The annotation rules (label, widget_type, minimum, maximum, step, group,
    option_N_value / option_N_label) follow obs-shaderfilter 2.6.0 by Exeldro
    (https://github.com/exeldro/obs-shaderfilter, GPL-2.0).

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 2 of the License, or
    (at your option) any later version.
******************************************************************************/

#include <cmath>
#include <cstring>
#include <map>
#include <set>
#include <string>
#include <filesystem>
#include <obs-module.h>
#include "shaderfilter_params.h"

namespace {

/* Uniforms that the engine sets itself. They get no setting. */
const std::set<std::string> builtin_names = {
    "ViewProj", "image", "uv_offset", "uv_scale", "uv_pixel_interval", "uv_size",
    "rand_f", "rand_instance_f", "rand_activation_f",
    "elapsed_time", "elapsed_time_start", "elapsed_time_show", "elapsed_time_active", "elapsed_time_enable",
    "loops", "loop_second", "local_time", "previous_image", "previous_output", "image_prev",
    "iTime", "iTimeDelta", "iFrame", "iResolution", "iSampleRate",
    "time", "delta_time", "frame_index", "upixel", "vpixel", "rand_seed", "current_step", "nb_steps",
    "pass_index", "pass_size", "pass_texel", "iteration", "iterations",
};

struct annotations {
    std::string label;
    std::string widget_type;
    std::string group;
    bool has_min = false, has_max = false, has_step = false;
    double min = 0, max = 0, step = 0;
    std::map<int, int> option_values;
    std::map<int, std::string> option_labels;
};

annotations read_annotations(gs_eparam_t *param) {
    annotations a;
    const size_t count = gs_param_get_num_annotations(param);
    for (size_t i = 0; i < count; i++) {
        gs_eparam_t *annotation = gs_param_get_annotation_by_idx(param, i);
        gs_effect_param_info info{};
        gs_effect_get_param_info(annotation, &info);
        void *val = gs_effect_get_default_val(annotation);
        if (val == nullptr) {
            continue;
        }
        const std::string n = info.name;
        const bool is_float = info.type == GS_SHADER_PARAM_FLOAT || info.type == GS_SHADER_PARAM_VEC2 ||
                              info.type == GS_SHADER_PARAM_VEC3 || info.type == GS_SHADER_PARAM_VEC4;
        const bool is_int = info.type == GS_SHADER_PARAM_INT;
        auto number = [&]() -> double {
            if (is_float) return *(float *)val;
            if (is_int) return *(int *)val;
            return 0.0;
        };
        if ((n == "name" || n == "label") && info.type == GS_SHADER_PARAM_STRING) {
            a.label = (const char *)val;
        }
        else if (n == "widget_type" && info.type == GS_SHADER_PARAM_STRING) {
            a.widget_type = (const char *)val;
        }
        else if (n == "group" && info.type == GS_SHADER_PARAM_STRING) {
            a.group = (const char *)val;
        }
        else if (n == "minimum" && (is_float || is_int)) {
            a.has_min = true;
            a.min = number();
        }
        else if (n == "maximum" && (is_float || is_int)) {
            a.has_max = true;
            a.max = number();
        }
        else if (n == "step" && (is_float || is_int)) {
            a.has_step = true;
            a.step = number();
        }
        else if (n.rfind("option_", 0) == 0) {
            const int id = atoi(n.c_str() + 7);
            if (is_int) {
                a.option_values[id] = *(int *)val;
            }
            else if (info.type == GS_SHADER_PARAM_STRING) {
                a.option_labels[id] = (const char *)val;
            }
        }
        bfree(val);
    }
    return a;
}

std::string display_name(const std::string &name, const annotations &a) {
    if (!a.label.empty()) {
        return a.label;
    }
    std::string out = name;
    for (auto &c : out) {
        if (c == '_') c = ' ';
    }
    return out;
}

std::string color_hex(const float *v, const bool alpha) {
    auto to_byte = [](float f) {
        f = std::fmax(0.0f, std::fmin(1.0f, f));
        return (int)std::lround(f * 255.0f);
    };
    char buf[16];
    snprintf(buf, sizeof(buf), "#%02X%02X%02X%02X", alpha ? to_byte(v[3]) : 255, to_byte(v[0]), to_byte(v[1]),
             to_byte(v[2]));
    return buf;
}

void set_range(json_t *p, const annotations &a, const bool is_int) {
    double min = a.min, max = a.max, step = a.step;
    // obs-shaderfilter: without a range, use -1000..1000.
    if (!a.has_min || !a.has_max || min == max) {
        min = -1000.0;
        max = 1000.0;
        step = is_int ? 1.0 : 0.0001;
    }
    if (!a.has_step || step == 0.0) {
        step = is_int ? 1.0 : 0.0001;
    }
    json_object_set_new(p, "min", is_int ? json_integer((json_int_t)min) : json_real(min));
    json_object_set_new(p, "max", is_int ? json_integer((json_int_t)max) : json_real(max));
    json_object_set_new(p, "step", is_int ? json_integer((json_int_t)step) : json_real(step));
}

} // namespace

bool shaderfilter_is_transition_source(const std::string &text) {
    return text.find("image_a") != std::string::npos && text.find("image_b") != std::string::npos;
}

json_t *shaderfilter_build_parameters(gs_effect_t *effect, const std::string &shader_path) {
    json_t *params = json_array();
    if (effect == nullptr) {
        return params;
    }
    const std::string textures_dir = (std::filesystem::path(shader_path).parent_path() / "textures").string();
    bool audio_added = false;

    // Group parameters with a "group" annotation, in order of first appearance.
    std::map<std::string, json_t *> groups;

    const size_t count = gs_effect_get_num_params(effect);
    for (size_t idx = 0; idx < count; idx++) {
        gs_eparam_t *param = gs_effect_get_param_by_idx(effect, idx);
        if (param == nullptr) {
            continue;
        }
        gs_effect_param_info info{};
        gs_effect_get_param_info(param, &info);
        const std::string name = info.name;
        if (builtin_names.count(name) != 0) {
            continue;
        }

        if (name == "audio_peak" || name == "audio_magnitude") {
            if (!audio_added) {
                audio_added = true;
                json_t *p = json_object();
                json_object_set_new(p, "type", json_string("audiolevel"));
                json_object_set_new(p, "name", json_string(name.c_str()));
                json_object_set_new(p, "label", json_string("Audio source"));
                json_object_set_new(p, "linear", json_true());
                json_array_append_new(params, p);
            }
            continue;
        }

        const annotations a = read_annotations(param);
        void *def = gs_effect_get_default_val(param);
        json_t *p = json_object();
        json_object_set_new(p, "name", json_string(name.c_str()));
        json_object_set_new(p, "label", json_string(display_name(name, a).c_str()));
        bool keep = true;

        switch (info.type) {
            case GS_SHADER_PARAM_BOOL:
                json_object_set_new(p, "type", json_string("bool"));
                json_object_set_new(p, "default", json_boolean(def != nullptr && *(bool *)def));
                break;
            case GS_SHADER_PARAM_FLOAT:
                json_object_set_new(p, "type", json_string("float"));
                json_object_set_new(p, "slider", json_boolean(a.widget_type == "slider"));
                set_range(p, a, false);
                json_object_set_new(p, "default", json_real(def != nullptr ? *(float *)def : 0.0));
                break;
            case GS_SHADER_PARAM_INT:
                if (a.widget_type == "select") {
                    json_object_set_new(p, "type", json_string("list_int"));
                    json_t *values = json_array();
                    for (auto &[id, value] : a.option_values) {
                        json_t *v = json_object();
                        json_object_set_new(v, "value", json_integer(value));
                        auto it = a.option_labels.find(id);
                        json_object_set_new(v, "label", json_string(it != a.option_labels.end() ? it->second.c_str() : std::to_string(value).c_str()));
                        json_array_append_new(values, v);
                    }
                    json_object_set_new(p, "values", values);
                }
                else {
                    json_object_set_new(p, "type", json_string("int"));
                    json_object_set_new(p, "slider", json_boolean(a.widget_type == "slider"));
                    set_range(p, a, true);
                }
                json_object_set_new(p, "default", json_integer(def != nullptr ? *(int *)def : 0));
                break;
            case GS_SHADER_PARAM_VEC2:
            case GS_SHADER_PARAM_VEC3:
            case GS_SHADER_PARAM_VEC4: {
                const int n = info.type == GS_SHADER_PARAM_VEC2 ? 2 : (info.type == GS_SHADER_PARAM_VEC3 ? 3 : 4);
                const auto *v = static_cast<const float *>(def);
                if (n >= 3 && a.widget_type != "slider") {
                    float c[4] = {1, 1, 1, 1};
                    for (int i = 0; v != nullptr && i < n; i++) c[i] = v[i];
                    json_object_set_new(p, "type", json_string("color"));
                    json_object_set_new(p, "default", json_string(color_hex(c, n == 4).c_str()));
                }
                else {
                    json_object_set_new(p, "type", json_string("vector"));
                    json_object_set_new(p, "slider", json_boolean(a.widget_type == "slider"));
                    set_range(p, a, false);
                    json_t *d = json_array();
                    for (int i = 0; i < n; i++) json_array_append_new(d, json_real(v != nullptr ? v[i] : 0.0));
                    json_object_set_new(p, "default", d);
                    if (!a.option_labels.empty()) {
                        json_t *labels = json_array();
                        for (auto &[id, l] : a.option_labels) json_array_append_new(labels, json_string(l.c_str()));
                        json_object_set_new(p, "labels", labels);
                    }
                }
                break;
            }
            case GS_SHADER_PARAM_TEXTURE:
                if (a.widget_type == "source") {
                    json_object_set_new(p, "type", json_string("source"));
                }
                else {
                    json_object_set_new(p, "type", json_string("image"));
                    json_object_set_new(p, "allow_custom", json_true());
                    // A default like `= "noise.png"` loads from textures/ next to the shader.
                    const char *file = def != nullptr ? static_cast<const char *>(def) : "";
                    if (file[0] != '\0') {
                        json_object_set_new(p, "default", json_string((textures_dir + "/" + file).c_str()));
                    }
                }
                break;
            case GS_SHADER_PARAM_STRING:
                if (a.widget_type == "info") {
                    json_object_set_new(p, "type", json_string("text"));
                    json_object_set_new(p, "value", json_string(def != nullptr ? (const char *)def : ""));
                }
                else {
                    keep = false;
                }
                break;
            default:
                keep = false;
                break;
        }
        bfree(def);

        if (!keep) {
            json_decref(p);
            continue;
        }
        if (!a.group.empty()) {
            auto it = groups.find(a.group);
            if (it == groups.end()) {
                json_t *g = json_object();
                json_object_set_new(g, "type", json_string("group"));
                json_object_set_new(g, "name", json_string(a.group.c_str()));
                json_object_set_new(g, "label", json_string(a.group.c_str()));
                json_object_set_new(g, "parameters", json_array());
                json_array_append_new(params, g);
                it = groups.emplace(a.group, g).first;
            }
            json_array_append_new(json_object_get(it->second, "parameters"), p);
        }
        else {
            json_array_append_new(params, p);
        }
    }
    return params;
}
