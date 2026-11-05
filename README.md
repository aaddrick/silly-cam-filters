# Silly Cam Filters

One OBS Studio plugin that holds shader filters, face-tracking filters and retro filters, plus a place to write new filters of your own.

I built it for "Silly Cam", a scene collection of goofy webcam effects for video calls. Before this plugin, the effects came from three separate plugins that I had to build by hand after every OBS update. Now there is one plugin, one build and one install script.

> **Status:** early. It builds and runs on Fedora Linux with OBS 32.2. I have not tested Windows or macOS builds.

## Credits

This plugin is a combination of three open-source OBS plugins. Almost all of the filter code, the shaders and the face-tracking work is theirs. Please star and support the original projects.

| Part of this plugin | Original project | Author(s) | License |
|---|---|---|---|
| `families/shaderfilter/`, `data/shaderfilter/` | [obs-shaderfilter](https://github.com/exeldro/obs-shaderfilter) 2.6.0 | [Exeldro](https://github.com/exeldro). Earlier versions by [Charles Fettinger](https://github.com/Oncorporation/obs-shaderfilter) and [nleseul](https://github.com/nleseul/obs-shaderfilter). The example shaders have many authors, named in each file. | GPL-2.0 |
| `families/shadertastic/`, `data/shadertastic/` | [Shadertastic](https://github.com/xurei/obs-shadertastic) 1.3.0 ([shadertastic.com](https://shadertastic.com)) | [xurei](https://github.com/xurei) | GPL-2.0 |
| `families/retro-effects/`, `data/retro-effects/` | [OBS Retro Effects](https://github.com/FiniteSingularity/obs-retro-effects) 1.0.2 | [FiniteSingularity](https://github.com/FiniteSingularity) | GPL-2.0 |
| `cmake/` | [obs-plugintemplate](https://github.com/obsproject/obs-plugintemplate), as changed by Shadertastic | OBS Project, xurei | GPL-2.0 |
| `vendor/libzip/` | [libzip](https://libzip.org) | Dieter Baron, Thomas Klausner | BSD-3-Clause |

The build also downloads these libraries, and the install puts the first one next to the plugin:

- [ONNX Runtime](https://github.com/microsoft/onnxruntime) 1.27.1, by Microsoft (MIT). It runs the face-tracking models.
- [OpenCV](https://opencv.org) 4.9.0, static build from [obs-backgroundremoval-dep-opencv](https://github.com/obs-ai/obs-backgroundremoval-dep-opencv) (Apache-2.0).

The face detection and face landmark models in `data/shadertastic/face_detection_models/` come from Google [MediaPipe](https://github.com/google-ai-edge/mediapipe) (Apache-2.0), converted to ONNX by the Shadertastic project.

[UPSTREAM.md](UPSTREAM.md) lists the exact upstream commits and every change I made to the upstream code.

## What you get in OBS

| Filter (OBS name) | Filter ID | Comes from |
|---|---|---|
| User-defined shader | `shader_filter` | obs-shaderfilter |
| User-defined transition | `shader_transition` | obs-shaderfilter |
| Shadertastic | `shadertastic_filter` | Shadertastic |
| Shadertastic transition | `shadertastic_transition` | Shadertastic |
| Retro Effects | `obs_retro_effects_filter` | OBS Retro Effects |
| Silly Mirror | `silly_mirror_filter` | this project |

The filter IDs are the same as in the original plugins. Scenes that use the original plugins keep working, after one path fix (see [Install](#install)).

## Install (Fedora)

Requirements: `obs-studio-devel`, `cmake`, `ninja-build`, `gcc-c++`, `qt6-qtbase-devel`, `jansson-devel`, `zlib-devel`, `patchelf`.

1. Close OBS.
2. Run `scripts/install.sh`. It builds the plugin and installs it into `/usr/lib64/obs-plugins/` (it uses `sudo`).
   - If the original obs-shaderfilter, Shadertastic or Retro Effects plugins are installed, the script moves them to `~/.local/share/silly-cam-filters/replaced-plugins-<date>/`. They register the same filter IDs, so OBS cannot load them next to this plugin.
3. Run `scripts/migrate-scene-collections.sh`. obs-shaderfilter filters store the full path of their shader file. This script changes those paths to the new data folder and keeps a backup of each scene collection.
4. Start OBS. The log shows `[silly-cam-filters] loading version ...`.

After an OBS update, run `scripts/install.sh` again.

## Data layout

Each original plugin keeps its own folder, so its files keep their original relative paths:

```
/usr/share/obs/obs-plugins/silly-cam-filters/
  locale/            text for this plugin's own filters
  silly/             shaders for this plugin's own filters
  shaderfilter/      examples/, textures/, internal/, locale/
  shadertastic/      effects/, face_detection_models/, locale/
  retro-effects/     shaders/, images/, presets/, locale/
/usr/lib64/obs-plugins/silly-cam-filters/
  libonnxruntime.so.1.27.1
```

Shadertastic settings move from `plugin_config/shadertastic/` to `plugin_config/silly-cam-filters/shadertastic/`.

## How the combination works

An OBS plugin is a shared library with one set of hooks: `obs_module_load()`, `obs_module_text()`, `obs_module_file()` and others. Each original plugin defines its own copy of these hooks, so they cannot simply be linked into one library.

The build compiles each original plugin (a "family") with its hooks renamed by the preprocessor. For example, the Retro Effects code is compiled with `-Dobs_module_load=scf_retro_load` and `-Dobs_find_module_file=scf_retro_find_module_file`. Then:

- `src/plugin.c` is the only real OBS module. It calls each family's renamed hooks.
- `src/scf-family.c` implements the renamed file, config and translation hooks. It sends each family to its own folder in `data/`.

Because of this, the upstream code needs almost no source changes, and new upstream versions are easy to merge. `scf_add_family()` in `CMakeLists.txt` sets up the renames.

## Add a filter

The quickest way is a shader file, with no build:

- **obs-shaderfilter:** put a `.shader` file in `data/shaderfilter/examples/`. Then add a "User-defined shader" filter in OBS and select the file. See the [obs-shaderfilter README](https://github.com/exeldro/obs-shaderfilter) for the file format.
- **Shadertastic:** put an effect folder (`main.hlsl` and `meta.json`) in `data/shadertastic/effects/filters/`. Shadertastic effects can use face tracking. See the [Shadertastic docs](https://shadertastic.com).

For a filter with its own C code and settings, use Silly Mirror as the template:

1. Copy `src/silly/mirror-filter.c` to `src/silly/<name>-filter.c`. Change the `id`, the names and the settings.
2. Copy `data/silly/mirror.effect` to `data/silly/<name>.effect` and write the shader.
3. Add the text strings to `data/locale/en-US.ini`.
4. Add an `extern` line and an `obs_register_source()` line to `src/silly/silly-filters.c`.
5. Run `scripts/install.sh`.

CMake finds every `.c` file in `src/silly/` without a change to `CMakeLists.txt`.

## License

GPL-2.0. See [LICENSE](LICENSE). The three original plugins are GPL-2.0, so this combination is GPL-2.0 too. libzip in `vendor/libzip/` keeps its BSD-3-Clause license.
