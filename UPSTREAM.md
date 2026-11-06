# Upstream sources

| Project | Upstream | Tag | Commit |
|---|---|---|---|
| Shadertastic | https://github.com/xurei/obs-shadertastic | 1.3.0 | `bc993f1887999b9c20ba3509f08c2799b5fba24c` |
| obs-shaderfilter | https://github.com/exeldro/obs-shaderfilter | 2.6.0 | `3517829fdd984a8c655973bf11a31a4852365ab7` |
| OBS Retro Effects | https://github.com/FiniteSingularity/obs-retro-effects | 1.0.2 | `35e9616a6f08692777578e3559d464ff8705929e` |

libzip in `vendor/libzip/` is the submodule commit that Shadertastic 1.3.0 uses.

## Shadertastic → the engine

| From upstream | To |
|---|---|
| `src/`, `onnxmediapipe/` | `engine/` |
| `data/` | `data/engine/` |
| `cmake/` | `cmake/` |
| `vendor/libzip/` | `vendor/libzip/` |

Changes:
- New files: `engine/src/engine_render.*` (passes, built-in values, frame history), `engine/src/legacy_compat.*` (settings conversion), `engine/src/shader/shaderfilter_*` (obs-shaderfilter template and settings), `engine/src/parameters/parameter_vector.hpp`.
- Changed:
  - `effect.*`: passes and obs-shaderfilter files
  - `shader/shader.*`: dialects, built-in setters and a pixel-unit sprite
  - `shader/shaders_library.cpp`: single-file shaders
  - `shader_filter.*`: lazy loading, the pass render loop and the built-in values
  - `shadertastic.cpp`: the effect list, plus the `silly_effect` ID and its aliases
  - `parameters/parameter_color_alpha.hpp`: `float3` colors
  - `parameters/parameter_image.hpp`: absolute default paths
  - `parameters/parameter_audiolevel.hpp`: a `linear` option
  - `parameters/parameter_factory.cpp`, `parameter_datatype.hpp`: the `vector` type
- Changed on the `feature/25-new-effects` branch (for the 25 new effects):
  - `shader/shader.cpp`: `@include` also searches the user `engine/include/` folder and the shipped `data/engine/include/` folder, and logs each included file (0d6ecc7).
  - `parameters/parameter_facetracking.hpp`: the face mesh pre-raster runs once per frame, not once per pass and iteration (e7cf02f).
  - `parameters/parameter_facetracking.hpp`: fixed the "no face" bounding box (a missing comma) and an out-of-bounds read of the bbox landmark list (310 entries read from a 246-entry array) (00ab331).
  - `parameters/parameter_facetracking.hpp`: face textures are unbound when the face is lost (reset mode) or before tracking starts, because compiled effects are shared between filters and a stale binding could point at another filter's or a freed texture (a0b3e50).
  - `parameters/parameter_image.hpp`: "Use custom file" on an image param with bundled values never loaded the chosen file (the settings key was built from the effect name, not the param's full name); fixed (4a48384). This bug is in upstream Shadertastic 1.3.0 too.
- Each change is marked with a "Silly Cam Filters engine" comment.
- `version.h` is a fixed file in place of the CMake-generated `version.h.in`.
- `win_dll_overrides.cpp` is not compiled (Windows only).

## obs-shaderfilter

- `data/examples/` → `data/engine/shaders/`, and `data/textures/` → `data/engine/shaders/textures/`, unchanged.
- The effect template (`effect_template_begin`/`_end`) is in `engine/src/shader/shaderfilter_template.h`.
- The rules for settings from uniform annotations are reimplemented in `engine/src/shader/shaderfilter_params.cpp`.
- The plugin's C code is not used.

## OBS Retro Effects

The 15 filters were ported by hand from the C code and shaders to engine effects in `data/engine/effects/filters/retro_*`. The ports aim to look and behave the same, but they are not exact copies:

- **Random values** come from shader hashes, not the original random number generators.
- **CPU state** (timers, glitch layouts, roll offsets) lives in 1×1 `rgba32f` state passes.
- **Cathode Boot** has a new automatic mode (power on/off when shown). Converted filters keep manual mode.
- **VHS** applies the author's intended wrinkle default. Converted filters keep the original's "no wrinkles" behaviour.
- **Scanlines** draws a real saw-tooth wave for "Saw-Tooth". Converted filters keep the original's sine wave.
- **Settings dropped** because the original never used them: `scanlines_offset`, `crt_phosphor_width/height`, `analog_glitch_interference_speed/scale`.

The original C code is not used.
