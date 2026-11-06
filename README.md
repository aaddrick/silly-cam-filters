# Silly Cam Filters

An OBS Studio plugin with one filter, **Silly Effect**, that runs every effect: 158 shader effects, 30 multi-pass and face-tracking effects, and a place to write your own.

I built it for "Silly Cam", a scene collection of goofy webcam effects for video calls: one scene per effect, each with its own settings. Before this plugin, the effects came from three separate plugins with three different effect formats. Now one engine runs them all.

> **Status:** early. It builds and runs on Fedora Linux with OBS 32.2 (OpenGL). I have not tested Windows or macOS.

## Credits

This plugin is built from three open-source OBS plugins. Almost all of the effects, the shaders and the face-tracking work are theirs. Please star and support the original projects.

| Part of this plugin | Original project | Author(s) | License |
|---|---|---|---|
| `engine/` (the effect engine, face tracking, settings UI) | [Shadertastic](https://github.com/xurei/obs-shadertastic) 1.3.0 ([shadertastic.com](https://shadertastic.com)) | [xurei](https://github.com/xurei) | GPL-2.0 |
| `data/engine/effects/filters/` (14 effects), `data/engine/effects/transitions/` | Shadertastic 1.3.0 | xurei | GPL-2.0 |
| `data/engine/shaders/` (163 shaders and textures), `engine/src/shader/shaderfilter_*` | [obs-shaderfilter](https://github.com/exeldro/obs-shaderfilter) 2.6.0 | [Exeldro](https://github.com/exeldro). Earlier versions by [Charles Fettinger](https://github.com/Oncorporation/obs-shaderfilter) and [nleseul](https://github.com/nleseul/obs-shaderfilter). The shaders have many authors, named in each file. | GPL-2.0 |
| `data/engine/effects/filters/retro_*` (15 effects) | [OBS Retro Effects](https://github.com/FiniteSingularity/obs-retro-effects) 1.0.2, ported from C to engine effects | [FiniteSingularity](https://github.com/FiniteSingularity) | GPL-2.0 |
| `cmake/` | [obs-plugintemplate](https://github.com/obsproject/obs-plugintemplate), as changed by Shadertastic | OBS Project, xurei | GPL-2.0 |
| `vendor/libzip/` | [libzip](https://libzip.org) | Dieter Baron, Thomas Klausner | BSD-3-Clause |

The build also downloads these libraries, and the install puts the first one next to the plugin:

- [ONNX Runtime](https://github.com/microsoft/onnxruntime) 1.27.1, by Microsoft (MIT). It runs the face-tracking models.
- [OpenCV](https://opencv.org) 4.9.0, static build from [obs-backgroundremoval-dep-opencv](https://github.com/obs-ai/obs-backgroundremoval-dep-opencv) (Apache-2.0).

The face detection and face landmark models in `data/engine/face_detection_models/` come from Google [MediaPipe](https://github.com/google-ai-edge/mediapipe) (Apache-2.0), converted to ONNX by the Shadertastic project.

[UPSTREAM.md](UPSTREAM.md) lists the upstream versions and what I changed.

## What you get in OBS

Add the **Silly Effect** filter to a source or scene, and pick an effect from the list. Each filter keeps its own settings.

| Effects | Count | Format |
|---|---|---|
| Shaders from obs-shaderfilter (bulge, swirl, fisheye, ASCII, thermal, cartoon, ...) | 158 | single `.shader` / `.effect` files |
| Shadertastic effects (laser eyes, face melt, face zoom, ghost, recursion, shake, ...) | 14 | effect folders, some with face tracking |
| Retro Effects (CRT, VHS, NTSC, matrix rain, digital and analog glitch, dither, ...) | 15 | multi-pass effect folders |
| Glow | 1 | multi-pass example |
| Color Correction | 1 | port of OBS's built-in Color Correction filter, same settings |

The plugin also opens filters saved by the original plugins. `shader_filter` (obs-shaderfilter), `obs_retro_effects_filter` (Retro Effects) and `shadertastic_filter` (Shadertastic) are hidden aliases of Silly Effect. Their settings are converted when OBS loads them.

## Install (Fedora)

Requirements: `obs-studio-devel`, `cmake`, `ninja-build`, `gcc-c++`, `qt6-qtbase-devel`, `jansson-devel`, `zlib-devel`, `patchelf`.

1. Close OBS.
2. Run `scripts/install.sh`. It builds the plugin and installs it into `/usr/lib64/obs-plugins/` (it uses `sudo`).
   - If the original obs-shaderfilter, Shadertastic or Retro Effects plugins are installed, the script moves them to `~/.local/share/silly-cam-filters/replaced-plugins-<date>/`. They register the same filter IDs, so OBS cannot load them next to this plugin.
3. Start OBS. The log shows `[silly-cam-filters] loading version ...`.

After an OBS update, run `scripts/install.sh` again.

### Moving from the original plugins

Your scenes keep working: OBS loads the old filters through the aliases and converts their settings. To switch them to Silly Effect for good:

1. Start OBS once with each scene collection, then close OBS. OBS saves the converted settings.
2. Run `scripts/migrate-scene-collections.sh`. It changes the converted filters to `silly_effect` and keeps a backup of each collection.

## Add an effect

Full reference: [docs/ENGINE.md](docs/ENGINE.md).

Put your effects in `~/.config/obs-studio/plugin_config/silly-cam-filters/engine/effects/`. The engine reads that folder when a filter is created, so you do not need to rebuild the plugin.

**A single shader file.** Save an obs-shaderfilter `.shader` file there. Its settings come from the uniforms:

```hlsl
uniform float strength<
    string label = "Strength";
    string widget_type = "slider";
    float minimum = 0.0;
    float maximum = 1.0;
    float step = 0.01;
> = 0.5;

float4 mainImage(VertData v_in) : TARGET
{
    float4 c = image.Sample(textureSampler, v_in.uv);
    return lerp(c, float4(1.0 - c.rgb, c.a), strength);
}
```

**A folder effect.** Make a folder with `meta.json` and `main.hlsl`. Folder effects can use:
- several render passes at different sizes
- the previous frame of any pass
- face tracking
- audio levels
- other OBS sources
- bundled images

`data/engine/effects/filters/glow/` is a small three-pass example.

**One rule for every shader:** each pixel shader must use its input coordinate (`v_in.uv`). On Linux, OBS draws nothing for a pass that ignores it. ENGINE.md explains this.

### A filter in C

For a filter that needs its own C code, use Silly Mirror as the template:

1. Copy `src/silly/mirror-filter.c` to `src/silly/<name>-filter.c`. Change the `id`, the names and the settings.
2. Copy `data/silly/mirror.effect` to `data/silly/<name>.effect` and write the shader.
3. Add the text strings to `data/locale/en-US.ini`.
4. Add an `extern` line and an `obs_register_source()` line to `src/silly/silly-filters.c`.
5. Run `scripts/install.sh`.

## How it is built

- `src/plugin.c` is the OBS module. It loads the engine and the C filters in `src/silly/`.
- `engine/` is the effect engine, which grew out of Shadertastic. The build compiles it with its OBS module hooks renamed (`scf_add_family()` in `CMakeLists.txt`), and `src/scf-family.c` sends its file and config lookups to `data/engine/` and `plugin_config/silly-cam-filters/engine/`.
- The engine adds to Shadertastic:
  - named render passes (`engine/src/engine_render.cpp`)
  - obs-shaderfilter shader files and their settings (`engine/src/shader/shaderfilter_params.cpp`)
  - the built-in values of both plugins
  - compiling only the effect a filter uses
  - settings conversion for the old filter IDs (`engine/src/legacy_compat.cpp`)

## License

GPL-2.0. See [LICENSE](LICENSE). The three original plugins are GPL-2.0, so this plugin is GPL-2.0 too. libzip in `vendor/libzip/` keeps its BSD-3-Clause license.
