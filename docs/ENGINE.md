# The Silly Cam Filters engine

One filter type, **Silly Effect** (`silly_effect`), runs every effect in this plugin. Each scene gets its own filter, and each filter has its own settings.

The engine grew out of the Shadertastic code by xurei. It keeps the Shadertastic effect format and adds:

- **Passes:** an effect can have several named render passes, at different sizes, that read each other's output.
- **obs-shaderfilter shaders:** a single `.shader` or `.effect` file is an effect. Its settings come from the shader code.
- **One set of built-in values** for all effects: the time, random numbers, sizes and textures of both Shadertastic and obs-shaderfilter.

## Where effects come from

The engine looks in these folders, in this order. When two effects have the same name, the engine uses the first one.

| Folder | Contents |
|---|---|
| `~/.config/obs-studio/plugin_config/silly-cam-filters/effects/` | your own effects (folders and shader files) |
| `<plugin data>/effects/` | effects that ship with the plugin |
| `<plugin data>/shaders/` | single-file shaders from obs-shaderfilter |

An effect is one of these:

1. **A folder** with `meta.json` and `main.hlsl`. The folder name is the effect name.
2. **A file** that ends in `.shader` or `.effect`, in obs-shaderfilter format. The effect name is the file name with each `.` changed to `_`, for example `BulgePinch_shader`.
3. **A Shadertastic bundle**, `<name>.filter.shadertastic` (a zip file of a folder effect).

## Folder effects

### meta.json

```json
{
  "metafileVersion": 1,
  "label": "Bloom",
  "about": { "author_name": "Someone", "author_url": "https://example.com" },
  "parameters": [ ... ],
  "passes": [ ... ]
}
```

- `label`: the name in the effect list.
- `parameters`: the settings. The engine uses the Shadertastic parameter types; see "Parameter types".
- `passes`: optional. Without `passes`, the effect is one pass (or uses the Shadertastic `steps`; see "Shadertastic steps").

### main.hlsl

`main.hlsl` is an OBS effect file (HLSL dialect). The engine adds this header in front of it, so do not declare these names yourself:

```hlsl
uniform float4x4 ViewProj;
uniform texture2d image;        // the source (the webcam, the scene, ...)
uniform texture2d tex_a, tex_b; // transitions only
uniform texture2d tex_interm;   // Shadertastic steps: the output of the previous step
uniform int   frame_index;      // frames since the filter became visible
uniform float time;             // seconds since the filter became visible
uniform bool  is_studio_mode;
uniform float delta_time;       // seconds since the previous frame
uniform float upixel, vpixel;   // the size of one source pixel in UV units
uniform float rand_seed;        // random 0..1, fixed for each filter
uniform int   current_step, nb_steps;
```

The header also defines `srgb_nonlinear_to_linear()`, `srgb_linear_to_nonlinear()`, `frac`/`fract`, `facetracking_sampler` and the face-tracking macros.

Each pass is one `technique` in `main.hlsl`. A single-pass effect uses `technique Draw`.

### Passes

```json
"passes": [
  { "name": "bright", "technique": "Bright", "scale": 0.5 },
  { "name": "blur",   "technique": "Blur",   "scale": 0.5, "iterations": 4 },
  { "name": "out",    "technique": "Combine" }
]
```

| Key | Meaning | Default |
|---|---|---|
| `name` | The pass name. It must be a valid HLSL name and must not be a name from the header. | required |
| `technique` | The technique in `main.hlsl` that draws this pass. | `Draw` |
| `scale` | The size of the pass output, as a part of the source size. `0.5` is half width and half height. | `1.0` |
| `iterations` | How many times the pass runs. A number, or the name of an `int` or `float` parameter. | `1` |
| `format` | `rgba16` (default), `rgba16f` or `rgba32f`. Use `rgba32f` for simulations that store data in pixels. | `rgba16` |

The engine runs the passes in order. The output of the last pass is the output of the filter.

**Inputs.** Declare a `texture2d` uniform with one of these names, and the engine binds it:

| Uniform | Contents |
|---|---|
| `image` | the source |
| `<pass>` | the output of an earlier pass in this frame. Inside an iterated pass, `<own name>` is the output of the previous iteration (on the first iteration, the output of the previous frame, or transparent). |
| `<pass>_prev` | the output of that pass in the previous frame (any pass, also later ones and the pass itself). The engine keeps a copy only when an effect declares this uniform. |
| `image_prev` | the source in the previous frame |

**Values for each pass:**

| Uniform | Type | Contents |
|---|---|---|
| `pass_index` | `int` | index of the pass, from 0 |
| `pass_size` | `float2` | output size of the pass, in pixels |
| `pass_texel` | `float2` | `1 / pass_size` |
| `iteration` | `int` | iteration index inside an iterated pass, from 0 |
| `iterations` | `int` | iteration count of this pass |

Sample a pass texture with UVs from 0 to 1, like `image`. The pass size does not change the UVs.

### Shadertastic steps

An effect with `"steps": N` and no `passes` works as in Shadertastic: technique `Draw` runs N times, `current_step` counts from 0, and `tex_interm` holds the previous step's output. A `prev_frame` parameter with `"step": k` keeps the output of step k for the next frame.

## Built-in values

The engine sets these uniforms in every effect that declares them, in addition to the header above. obs-shaderfilter shaders get them from their own header.

| Uniform | Type | Contents |
|---|---|---|
| `elapsed_time` | `float` | seconds since the filter was created |
| `elapsed_time_start` | `float` | seconds since the effect was loaded |
| `elapsed_time_show` | `float` | seconds the source has been showing |
| `elapsed_time_active` | `float` | seconds the source has been active (on the program output) |
| `elapsed_time_enable` | `float` | seconds since the filter was enabled |
| `loops` | `int` | whole seconds of `elapsed_time` |
| `loop_second` | `float` | `elapsed_time` modulo 1 |
| `local_time` | `float` | the system clock, in seconds |
| `rand_f` | `float` | random 0..1, new each frame |
| `rand_instance_f` | `float` | random 0..1, fixed for each filter |
| `rand_activation_f` | `float` | random 0..1, new each time the filter is enabled |
| `uv_size` | `float2` | source size in pixels |
| `uv_pixel_interval` | `float2` | `1 / uv_size` |
| `uv_offset`, `uv_scale` | `float2` | `(0,0)` and `(1,1)` |
| `previous_image` | `texture2d` | the source in the previous frame |
| `previous_output` | `texture2d` | the filter output in the previous frame |
| `iTime`, `iTimeDelta`, `iFrame` | `float` | Shadertoy names for `time`, `delta_time`, `frame_index` |
| `iResolution` | `float3` | `(width, height, 1)` |

## Parameter types

These are the Shadertastic parameter types. The parameter `name` must match a uniform in `main.hlsl`. Settings keys are `<effect>.<name>`.

| Type | Uniform | Notes |
|---|---|---|
| `float` / `double` | `float` | `min`, `max`, `step`, `slider`, `default` |
| `int` | `int` | `min`, `max`, `step`, `slider`, `default` |
| `bool` | `bool` | `default` |
| `color` | `float4` | `default` as `#RRGGBB` or `#AARRGGBB` |
| `list_int` | `int` | `values: [{ "value": 1, "label": "One" }]`, `default` |
| `image` | `texture2d` | a bundled image (`values` with files in the effect folder) and/or a file chooser |
| `source` | `texture2d` | another OBS source or scene |
| `audiolevel` | `float` | the level of an audio source, 0..1 |
| `facetracking` | `texture2d` | face landmarks; see Shadertastic's face tracking docs |
| `prev_frame` | `texture2d` | Shadertastic steps only; with passes, use `<pass>_prev` |
| `time` | `float` | a resettable timer with a speed setting |
| `text` | (none) | text in the settings window |
| `group` | (none) | a group of parameters |

Every parameter can have `label`, `description` and `if` (show it only when a condition on other settings is true).

## obs-shaderfilter shaders

A `.shader` file contains only the pixel shader, as in obs-shaderfilter. The engine wraps it in the obs-shaderfilter template: it adds the header (`image`, `elapsed_time`, `uv_size`, ..., `textureSampler`, `VertData`, `mainTransform`) and a `technique Draw` that calls `mainImage`.

A `.effect` file is a complete OBS effect with its own `technique Draw` (obs-shaderfilter's "override entire effect").

The engine reads the settings from the uniforms, as obs-shaderfilter does:

```hlsl
uniform float speed<
    string label = "Speed";
    string widget_type = "slider";
    float minimum = 0.0;
    float maximum = 10.0;
    float step = 0.1;
> = 2.0;
```

| Uniform type | Setting |
|---|---|
| `bool` | check box |
| `float` | number; a slider with `widget_type = "slider"` |
| `int` | number; a slider with `"slider"`; a list with `widget_type = "select"` and `option_0_value`, `option_0_label`, ... |
| `float3` | color |
| `float4` | color with alpha |
| `texture2d` | an image file; with `widget_type = "source"`, another OBS source. A default like `= "noise.png"` loads from the `textures/` folder next to the shader. |
| `string` with `widget_type = "info"` | text in the settings window |

`audio_peak` and `audio_magnitude` become an audio source setting.
