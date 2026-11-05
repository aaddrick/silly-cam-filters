# Upstream sources

| Family | Upstream | Tag | Commit |
|---|---|---|---|
| shaderfilter | https://github.com/exeldro/obs-shaderfilter | 2.6.0 | `3517829fdd984a8c655973bf11a31a4852365ab7` |
| shadertastic | https://github.com/xurei/obs-shadertastic | 1.3.0 | `bc993f1887999b9c20ba3509f08c2799b5fba24c` |
| retro | https://github.com/FiniteSingularity/obs-retro-effects | 1.0.2 | `35e9616a6f08692777578e3559d464ff8705929e` |

libzip in `vendor/libzip/` is the submodule commit that Shadertastic 1.3.0 uses.

## What I copied

| From upstream | To |
|---|---|
| obs-shaderfilter: `obs-shaderfilter.c`, `obs-shaderfilter.h` | `families/shaderfilter/` |
| obs-shaderfilter: `data/` | `data/shaderfilter/` |
| obs-shadertastic: `src/`, `onnxmediapipe/` | `families/shadertastic/` |
| obs-shadertastic: `data/` | `data/shadertastic/` |
| obs-shadertastic: `cmake/` | `cmake/` |
| obs-shadertastic: `vendor/libzip/` | `vendor/libzip/` |
| obs-retro-effects: `src/` | `families/retro-effects/` |
| obs-retro-effects: `data/` | `data/retro-effects/` |

## Changes to upstream code

- `version.h` in each family: a fixed file in place of the CMake-generated `version.h.in`.
- No other source changes. The build renames the OBS module hooks of each family. See `scf_add_family()` in `CMakeLists.txt`.
- Retro Effects is compiled with `create_or_reset_texrender` renamed to `scf_retro_create_or_reset_texrender`, because obs-shaderfilter defines a function with the same name.
- `families/shadertastic/src/win_dll_overrides.cpp` is not compiled (Windows only).

## Update a family to a new upstream version

1. Clone the upstream repository and check out the new tag.
2. Replace the family's files in `families/<family>/` and `data/<family>/` (see the table above).
3. Keep the fixed `version.h`, with the new version number.
4. Run `scripts/install.sh` and check the OBS log for link errors. A "multiple definition" error means two families now share a function name. Rename it as for `create_or_reset_texrender` in `CMakeLists.txt`.
5. Update the table at the top of this file.
