/******************************************************************************
    Silly Cam Filters engine: a float2, float3 or float4 parameter, shown as
    one number (or slider) per component. obs-shaderfilter shaders use this
    for vector uniforms with widget_type = "slider".

    Settings keys: <effect>.<name>_0, <effect>.<name>_1, ...

    JSON: {
      "type": "vector", "name": "offset", "components": 2,
      "labels": ["X", "Y"], "slider": true,
      "min": 0.0, "max": 1.0, "step": 0.01, "default": [0.5, 0.5]
    }

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 2 of the License, or
    (at your option) any later version.
******************************************************************************/

#ifndef SILLY_PARAMETER_VECTOR_HPP
#define SILLY_PARAMETER_VECTOR_HPP

#include <string>
#include <vector>
#include "parameter.hpp"

class effect_parameter_vector : public effect_parameter {
    private:
        int components = 2;
        bool slider = false;
        double min = -1000.0, max = 1000.0, step = 0.0001;
        float default_value[4]{};
        std::vector<std::string> labels;

        [[nodiscard]] std::string component_key(const char *effect_name, int i) const {
            return get_full_param_name(effect_name) + "_" + std::to_string(i);
        }

    public:
        explicit effect_parameter_vector(gs_eparam_t *shader_param) : effect_parameter(sizeof(float) * 4, shader_param) {
            if (shader_param != nullptr) {
                gs_effect_param_info info{};
                gs_effect_get_param_info(shader_param, &info);
                if (info.type == GS_SHADER_PARAM_VEC2) components = 2;
                else if (info.type == GS_SHADER_PARAM_VEC3) components = 3;
                else if (info.type == GS_SHADER_PARAM_VEC4) components = 4;
            }
            data_size = sizeof(float) * components;
        }

        [[nodiscard]] effect_param_datatype type() const override {
            return PARAM_DATATYPE_VECTOR;
        }

        void initialize_params(const std::string &effect_name, const effect_shader *shader, json_t *metadata, const std::string &effect_path) override {
            UNUSED_PARAMETER(effect_name);
            UNUSED_PARAMETER(shader);
            UNUSED_PARAMETER(effect_path);
            slider = json_bool_value_or(json_object_get(metadata, "slider"), false);
            min = json_number_value_or(json_object_get(metadata, "min"), -1000.0);
            max = json_number_value_or(json_object_get(metadata, "max"), 1000.0);
            step = json_number_value_or(json_object_get(metadata, "step"), 0.0001);
            json_t *def = json_object_get(metadata, "default");
            for (int i = 0; i < 4; i++) {
                default_value[i] = json_is_array(def) ? (float)json_number_value_or(json_array_get(def, i), 0.0) : 0.0f;
            }
            labels.clear();
            json_t *labels_json = json_object_get(metadata, "labels");
            for (int i = 0; i < components; i++) {
                json_t *l = json_is_array(labels_json) ? json_array_get(labels_json, i) : nullptr;
                if (json_is_string(l)) {
                    labels.emplace_back(json_string_value(l));
                }
                else {
                    static const char *suffix[] = {" X", " Y", " Z", " W"};
                    labels.emplace_back((label.empty() ? name : label) + suffix[i]);
                }
            }
        }

        void set_default(obs_data_t *settings, const char *effect_name) override {
            for (int i = 0; i < components; i++) {
                obs_data_set_default_double(settings, component_key(effect_name, i).c_str(), default_value[i]);
            }
        }

        void render_property_ui(const char *effect_name, obs_properties_t *props) override {
            for (int i = 0; i < components; i++) {
                std::string key = component_key(effect_name, i);
                if (slider) {
                    obs_properties_add_float_slider(props, key.c_str(), labels[i].c_str(), min, max, step);
                }
                else {
                    obs_properties_add_float(props, key.c_str(), labels[i].c_str(), min, max, step);
                }
            }
        }

        void apply_visible(const char *effect_name, obs_properties_t *props, const bool is_visible) override {
            for (int i = 0; i < components; i++) {
                auto *p = obs_properties_get(props, component_key(effect_name, i).c_str());
                if (p != nullptr) {
                    obs_property_set_visible(p, is_visible);
                }
            }
        }

        void set_data_from_settings(obs_data_t *settings, const char *effect_name) override {
            auto *v = static_cast<float *>(this->data);
            for (int i = 0; i < components; i++) {
                v[i] = (float)obs_data_get_double(settings, component_key(effect_name, i).c_str());
            }
        }
};

#endif // SILLY_PARAMETER_VECTOR_HPP
