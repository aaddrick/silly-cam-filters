/******************************************************************************
    Silly Cam Filters engine: open filters saved by obs-shaderfilter
    ("shader_filter") and obs-retro-effects ("obs_retro_effects_filter").

    Both IDs are registered as hidden aliases of the engine filter. When such
    a filter is created, its settings are converted once to the engine format:
      shader_file_name = ".../BulgePinch.shader", radius = 0.6
        -> effect = "BulgePinch_shader", effect_file = ".../BulgePinch.shader",
           BulgePinch_shader.radius = 0.6
      filter_type = 11, vhs_jitter_min_size = 2
        -> effect = "retro_vhs", retro_vhs.vhs_jitter_min_size = 2

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 2 of the License, or
    (at your option) any later version.
******************************************************************************/

#include <algorithm>
#include <cstring>
#include <set>
#include <string>
#include <vector>
#include <obs-module.h>
#include "legacy_compat.h"

namespace {

/* Copies one settings item to a new key. */
void copy_item(obs_data_t *settings, obs_data_item_t *item, const std::string &to) {
    switch (obs_data_item_gettype(item)) {
        case OBS_DATA_STRING:
            obs_data_set_string(settings, to.c_str(), obs_data_item_get_string(item));
            break;
        case OBS_DATA_NUMBER:
            if (obs_data_item_numtype(item) == OBS_DATA_NUM_INT) {
                obs_data_set_int(settings, to.c_str(), obs_data_item_get_int(item));
            }
            else {
                obs_data_set_double(settings, to.c_str(), obs_data_item_get_double(item));
            }
            break;
        case OBS_DATA_BOOLEAN:
            obs_data_set_bool(settings, to.c_str(), obs_data_item_get_bool(item));
            break;
        case OBS_DATA_OBJECT: {
            obs_data_t *obj = obs_data_item_get_obj(item);
            obs_data_set_obj(settings, to.c_str(), obj);
            obs_data_release(obj);
            break;
        }
        case OBS_DATA_ARRAY: {
            obs_data_array_t *arr = obs_data_item_get_array(item);
            obs_data_set_array(settings, to.c_str(), arr);
            obs_data_array_release(arr);
            break;
        }
        default:
            break;
    }
}

/* Moves every user setting not in `skip` to "<effect>.<key>". */
void prefix_settings(obs_data_t *settings, const std::string &effect, const std::set<std::string> &skip,
                     const std::string &strip_suffix = "") {
    std::vector<std::string> keys;
    for (obs_data_item_t *item = obs_data_first(settings); item != nullptr; obs_data_item_next(&item)) {
        if (!obs_data_item_has_user_value(item)) continue;
        const std::string key = obs_data_item_get_name(item);
        if (skip.count(key) != 0 || key.find('.') != std::string::npos) continue;
        keys.push_back(key);
    }
    for (const auto &key : keys) {
        obs_data_item_t *item = obs_data_item_byname(settings, key.c_str());
        if (item == nullptr) continue;
        std::string new_key = key;
        if (!strip_suffix.empty() && new_key.size() > strip_suffix.size() &&
            new_key.compare(new_key.size() - strip_suffix.size(), strip_suffix.size(), strip_suffix) == 0) {
            new_key = new_key.substr(0, new_key.size() - strip_suffix.size());
        }
        copy_item(settings, item, effect + "." + new_key);
        obs_data_item_release(&item);
        obs_data_erase(settings, key.c_str());
    }
}

void convert_shader_filter(obs_data_t *settings) {
    const char *file = obs_data_get_string(settings, "shader_file_name");
    if (file == nullptr || file[0] == '\0') {
        return; // inline shader text is not supported by the engine
    }
    std::string path = file;
    std::string name = path.substr(path.find_last_of("/\\") + 1);
    std::replace(name.begin(), name.end(), '.', '_');

    // obs-shaderfilter stores a texture source as "<name>_source"; the engine uses "<name>".
    // Its audio source setting becomes the audio parameter.
    std::string audio = obs_data_get_string(settings, "audio_source");
    prefix_settings(settings, name,
                    {"shader_file_name", "from_file", "override_entire_effect", "shader_text", "last_error",
                     "expand_left", "expand_right", "expand_top", "expand_bottom", "audio_source",
                     "use_shader_elapsed_time", "use_sliders", "reload_effect"},
                    "_source");
    if (!audio.empty()) {
        obs_data_set_string(settings, (name + ".audio_peak").c_str(), audio.c_str());
        obs_data_set_string(settings, (name + ".audio_magnitude").c_str(), audio.c_str());
    }
    obs_data_set_string(settings, "effect", name.c_str());
    obs_data_set_string(settings, "effect_file", path.c_str());
}

const char *retro_effect_name(const long long type) {
    switch (type) {
        case 1: return "retro_frame_skip";
        case 2: return "retro_interlace";
        case 3: return "retro_chromatic_aberration";
        case 4: return "retro_posterize";
        case 5: return "retro_dither";
        case 6: return "retro_crt";
        case 7: return "retro_ntsc";
        case 8: return "retro_cathode_boot";
        case 9: return "retro_matrix_rain";
        case 10: return "retro_codec";
        case 11: return "retro_vhs";
        case 12: return "retro_bloom";
        case 13: return "retro_scanlines";
        case 14: return "retro_digital_glitch";
        case 15: return "retro_analog_glitch";
        default: return nullptr;
    }
}

void convert_retro(obs_data_t *settings) {
    const long long type = obs_data_get_int(settings, "filter_type");
    const char *effect_c = retro_effect_name(type);
    if (effect_c == nullptr) {
        return;
    }
    const std::string effect = effect_c;
    const bool had_wrinkle = obs_data_has_user_value(settings, "vhs_wrinkle_occurrence");
    prefix_settings(settings, effect, {"filter_type"});

    // Keep the old look where the port differs from the original on purpose.
    if (type == 8) {
        // The original has no automatic power-on.
        obs_data_set_int(settings, (effect + ".cathode_boot_auto").c_str(), 0);
    }
    else if (type == 11 && !had_wrinkle) {
        // The original's default for wrinkles never applied (wrong key), so it drew none.
        obs_data_set_double(settings, (effect + ".vhs_wrinkle_occurrence").c_str(), 0.0);
    }
    else if (type == 13) {
        // The original drew a sine wave for "Saw-Tooth".
        const std::string key = effect + ".scanlines_profile";
        if (obs_data_get_int(settings, key.c_str()) == 2) {
            obs_data_set_int(settings, key.c_str(), 0);
        }
    }
    obs_data_set_string(settings, "effect", effect.c_str());
}

} // namespace

void engine_convert_legacy_settings(const char *source_id, obs_data_t *settings) {
    if (source_id == nullptr || settings == nullptr || obs_data_has_user_value(settings, "effect")) {
        return; // already in the engine format
    }
    if (strcmp(source_id, LEGACY_SHADER_FILTER_ID) == 0) {
        convert_shader_filter(settings);
    }
    else if (strcmp(source_id, LEGACY_RETRO_FILTER_ID) == 0) {
        convert_retro(settings);
    }
}
