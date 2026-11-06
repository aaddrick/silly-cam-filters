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
| `~/.config/obs-studio/plugin_config/silly-cam-filters/engine/effects/` | your own effects (folders and shader files) |
| `<plugin data>/engine/effects/filters/` | folder effects that ship with the plugin |
| `<plugin data>/engine/shaders/` | single-file shaders from obs-shaderfilter |

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

### Shared includes

A `main.hlsl` can paste in a shared file with a line of its own:

```hlsl
@include "silly_face.hlsl"
```

The engine looks for the file in these folders, in this order:

| Folder | Contents |
|---|---|
| the effect's own folder | files that belong to one effect |
| `~/.config/obs-studio/plugin_config/silly-cam-filters/engine/include/` | your own shared files; a file here replaces the shipped one with the same name |
| `<plugin data>/engine/include/` | shared files that ship with the plugin (`silly_face.hlsl`, `silly_framering.hlsl`) |

The `dev_mode_library_path` setting (Shadertastic dev mode) is also searched, after the effect's own folder. It is for developing the engine and shared files only. An installed plugin does not need it.

- Paths may contain folders (`@include "lib/x.hlsl"`). An included file can include others.
- A missing file stops the effect from loading ("Could not parse shader file" in the OBS log).
- Each `@include` line pastes the file again, so shared files need `#ifndef` guards.
- `@include` does not work inside `.shadertastic` zip bundles.
- `#define` before `@include` works, and so do `#ifdef`/`#ifndef`. `#if` with expressions does not.
- The OBS log has one line for each included file: `[shadertastic] <main.hlsl>: @include <path>`. A stale copy in your user folder that shadows the shipped file shows up there.
- The engine compiles each effect once per OBS session and shares it between all filters. Edits to `main.hlsl` or an included file take effect after OBS restarts.

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
| `size` | A fixed output size in pixels, `[width, height]`. Use `[1, 1]` for a pass that only stores state. It overrides `scale`. | none |
| `iterations` | How many times the pass runs. A number, or the name of an `int` or `float` parameter. The engine caps it at 64; to get more, chain several passes (for example 8 passes of 64 iterations). | `1` |
| `format` | `rgba16` (default), `rgba16f` or `rgba32f`. Use `rgba32f` for simulations that store data in pixels. | `rgba16` |

The engine runs the passes in order. The output of the last pass is the output of the filter.

**Inputs.** Declare a `texture2d` uniform with one of these names, and the engine binds it:

| Uniform | Contents |
|---|---|
| `image` | the source |
| `<pass>` | the output of an earlier pass in this frame. Inside an iterated pass, `<own name>` is the output of the previous iteration. **At iteration 0 it does not hold the previous frame**: read `<pass>_prev` there instead. A pass that is not iterated and reads its own name does get the previous frame. |
| `<pass>_prev` | the output of that pass in the previous frame (any pass, also later ones and the pass itself), in the pass's own format. The engine keeps a copy only when an effect declares this uniform. Before the first frame, it is transparent. |
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

**Every pixel shader must use its input coordinate (`v_in.uv`).** On Linux (OpenGL), OBS draws nothing for a pass whose pixel shader ignores it: a pass that returns a constant, or that only reads a texture at a fixed point, leaves its output empty. In a `size: [1, 1]` state pass, `v_in.uv` is the pixel center `(0.5, 0.5)`, so read the state with `state.Sample(sampler, v_in.uv)`.

### Shadertastic steps

An effect with `"steps": N` and no `passes` works as in Shadertastic: technique `Draw` runs N times, `current_step` counts from 0, and `tex_interm` holds the previous step's output. A `prev_frame` parameter with `"step": k` keeps the output of step k for the next frame.

## Face helpers (`silly_face.hlsl`)

`silly_face.hlsl` gives face effects the landmarks and masks, so they do not each carry their own triangle tables. Include it with `@include "silly_face.hlsl"`.

**Required parameter.** The face-tracking parameter must be named `fd`:

```json
{ "type": "facetracking", "name": "fd", "use_preraster": true,
  "reset_on_face_lost": { "prompt": true, "default": true } }
```

- `reset_on_face_lost` is required. Without it, `fd_face_found` never goes false, and stickers or eyes stay painted on an empty chair.
- `use_preraster` is required for the mask functions. Without it they report "outside" everywhere.
- The include declares `fd_face_found`, `fd_bbox_tl`, `fd_bbox_br`, `fd_points_tex` and `fd_preraster_tex` itself, so `main.hlsl` must not.
- The engine rasterises the face mesh once per frame, even when an effect has several passes or iterations.

**Conventions**

| Topic | Rule |
|---|---|
| UV | Positions are source UVs, 0..1, origin top-left, y down (like `v_in.uv`). |
| ISO | Distances, radii and scales are in units of the source height, with x corrected for the aspect ratio (`sf_to_iso(uv) = uv * float2(width/height, 1)`), so circles stay round. |
| Distances | Use `length(sf_to_iso(a) - sf_to_iso(b))`, never `length(a - b)` on UVs. |
| Left / right | The image side, for an upright face. |
| Angles | Radians. Positive is clockwise on screen. |
| Face frame | `sf_to_local(uv)` has its origin between the eye sockets (corner midpoints, so it does not move when the person looks around), x towards the image-right eye, y down the face, and the socket distance as its unit. The sockets are at (-0.5, 0) and (0.5, 0), and the mouth is near (0, 1). |
| Face oval | `sf_face_center()`, `sf_face_half_size_iso()` and the ellipse functions come from landmarks 10, 152, 234 and 454, in the face frame. `fd_bbox_*` is legacy (`sf_face_bbox()` only). |

**No face: use `sf_face_ok()`.** Start each pixel shader with `if (!sf_face_ok()) return image.Sample(...);`. The landmark values are stale or zero when no face is found. The mask functions return "outside" by themselves. Privacy effects (Face Censor) fail closed: when no face is found, they cover the whole frame.

**Presence fade.** `sf_presence_step(prev, seconds)`, run in a 1x1 `rgba16f` state pass, gives a 0..1 presence value. Use it to fade an effect in when a face appears. The snippet is in the include.

**Face lost.** With `reset_on_face_lost`, the engine drops the landmarks on the first frame without a face. A fade-out would need the effect to cache its anchors in a state pass, so the shipped effects do not do it: they pop back to the plain image. The fade-in on reacquire works.

| Group | Functions |
|---|---|
| validity, spaces | `sf_face_ok()`, `sf_aspect()`, `sf_to_iso`, `sf_from_iso`, `sf_px`, `sf_rotate(v, a)` |
| landmarks | `sf_lm(i)` (UV), `sf_lm_iso(i)`, `sf_lm3(i)` (with depth), `sf_canon(i)` (canonical model UV); named indices `SF_LM_*` |
| eyes (`_l` / `_r`) | `sf_eye_l_center()` (iris), `sf_eye_l_socket()` (corner midpoint), `sf_eye_l_radius()` (half width), `sf_iris_l_radius()`, `sf_eye_l_open()` (lid gap / width), `sf_eye_l_dist(uv)` (ellipse, 1 on the edge) |
| mouth, nose | `sf_mouth_center()`, `sf_mouth_open()` (gap / width, 0 closed), `sf_mouth_gap()`, `sf_mouth_width()`, `sf_mouth_dist(uv)`, `sf_nose_tip()` |
| head | `sf_roll()`, `sf_face_scale()` (socket distance), `sf_eyes_mid()`, `sf_face_x()`, `sf_face_y()`, `sf_presence_step(prev, s)` |
| face oval | `sf_face_center()`, `sf_face_half_size_iso()`, `sf_face_oval_local()`, `sf_face_ellipse_dist(uv)`, `sf_face_ellipse_dist_rolled(uv)`, legacy `sf_face_bbox()` |
| face frame | `sf_to_local(uv)`, `sf_from_local(p)`, `sf_local_to_uv_dir(d)`, `sf_midline_side(uv)`, `sf_mirror_midline(uv)` |
| masks | `sf_region_at(uv)` (`SF_REGION_NONE/FACE/EYE_L/EYE_R/MOUTH`), `sf_in_face`, `sf_in_eye_l`, `sf_in_eye_r`, `sf_in_eye`, `sf_in_mouth`, `sf_tri_at(uv)`, `sf_bary_at(uv)`, `sf_tri_vertices(tri)`, `sf_canon_at(uv)` |
| warps | `sf_bulge(uv, center, radius_iso, strength)`, `sf_swirl(uv, center, radius_iso, angle)` |

The full list, with units, is in the comments at the top of each function group in `data/engine/include/silly_face.hlsl`.

Masks are hard-edged (point-sampled). Use the `*_dist` ellipses where soft edges matter. `sf_in_mouth` is empty when the lips are closed. Each helper is one point fetch from a 478x4 texture, so compute the ones you need once at the top of the pixel shader.

## Frame ring (`silly_framering.hlsl`)

A frame ring keeps the last N frames of the source in one small texture (an *atlas*), so an effect can ask "what did the image look like k frames ago?". Use it for delays, slit-scan and delay grids. It is not for a freeze that must last longer than N-1 frames (the ring overwrites old slots); use your own `<pass>_prev` pass for that.

**Use it.** In `meta.json`, add a pass named exactly `ring`, before the passes that read it. Do not set `iterations`, and keep the default format.

```json
"passes": [
  { "name": "ring", "technique": "Ring", "scale": 1.0 },
  { "name": "out",  "technique": "Draw" }
]
```

In `main.hlsl`:

```hlsl
#define FR_G 3                       // the atlas is G x G cells
#define FR_N 9                       // slots used, 2..G*G (default G*G)
#define FR_ATLAS_SCALE 1.0           // must equal the "scale" of the ring pass (default 1.0)
#define FR_STRIDE 1                  // store every STRIDE-th frame (default 1)
// #define FR_BLEND                  // optional: fractional k blends two stored frames
@include "silly_framering.hlsl"

struct VertData { float2 uv : TEXCOORD0; float4 pos : POSITION; };
VertData VSDefault(VertData v_in) { VertData o; o.uv = v_in.uv; o.pos = mul(float4(v_in.pos.xyz, 1.0), ViewProj); return o; }

float4 PSRing(VertData v_in) : TARGET { return fr_ring_pixel(v_in.uv); }
float4 PSOut(VertData v_in)  : TARGET { return fr_sample(v_in.uv, 3.0); }   // 3 frames ago

technique Ring { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSRing(v_in); } }
technique Draw { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSOut(v_in); } }
```

The include declares `uniform texture2d ring;`, the samplers `fr_point` and `fr_linear`, and the functions below. An effect that includes it without a `ring` pass compiles but reads transparent black.

**Layout**
- The atlas has the source aspect ratio. Cell size = source size * `FR_ATLAS_SCALE` / `FR_G`. Slot s is column `s % G`, row `s / G` (row 0 on top).
- The ring pass reads its own name (`ring`, its output of the previous frame). It copies every slot with a point sample, and writes a 4-tap box-filtered copy of `image` into slot `(frame_index / FR_STRIDE) % FR_N`.
- `frame_index` restarts at 0 when the filter is shown or reloaded, and the valid-frame count restarts with it, so old slots are never read. On the first frame every delay returns the current frame (no black).
- Delay is counted in rendered frames: seconds = k / fps.
- At k = 0 you get the cell resolution. Sample `image` directly for a full-resolution "now".

**Functions**

| Name | Meaning |
|---|---|
| `fr_ring_pixel(float2 uv)` | the ring pass pixel shader body |
| `FR_COUNT` | stored frames valid now (1 on the first frame, up to `FR_N`) |
| `FR_MAX_K` | largest delay the ring can answer now, in frames (0 on the first frame) |
| `fr_clamp_k(k)`, `fr_has(k)` | clamp k to 0..`FR_MAX_K`; test `k <= FR_MAX_K` |
| `fr_sample(uv, k)` | the frame k ago at image uv (0..1). k is clamped. Nearest stored frame by default (exact for `FR_STRIDE` 1 and whole k); with `FR_BLEND` a fractional k blends the two neighbours. A per-pixel k is fine (slit-scan). |
| `fr_sample_i(uv, j)` | the j-th stored frame back (0 = newest), one tap |
| `fr_atlas_uv(uv, slot)` | image uv to atlas uv inside a slot (half-texel inset) |

**Parser quirks.** The engine's HLSL parser rejects zero-argument function calls and function-like macros with no arguments. That is why `FR_COUNT` and `FR_MAX_K` are written without parentheses. It also needs explicit `int()` and `float()` casts where HLSL would convert for you, so cast.

**Memory and cost.** Memory = 1920 * 1080 * 8 bytes * `FR_ATLAS_SCALE`^2 * 2 (rgba16 is 8 bytes per pixel; two buffers; no `_prev` copy).

| Config (1080p) | Atlas | Cell | Memory |
|---|---|---|---|
| N=9, G=3, scale 1.0 | 1920x1080 | 640x360 | 33 MB |
| N=16, G=4, scale 1.0 | 1920x1080 | 480x270 | 33 MB |
| N=25, G=5, scale 5/3 | 3200x1800 | 640x360 | 92 MB |
| N=9, G=3, scale 1.5 | 2880x1620 | 960x540 | 75 MB |

For 4K sources multiply by 4. The ring pass costs about one extra full-screen pass at scale 1.0.

**Recipe: 3x3 delay grid with 0.1 s steps (Delay Grid).** Use `FR_G 5`, `FR_N 25`, `FR_STRIDE 1`, `FR_ATLAS_SCALE 1.667`, and read cell i at a delay of about 2 to 3 frames per step. Prefer stride 1 with more slots over a larger stride: `FR_STRIDE = S` stores one frame in S, so delays reach (N-1)*S frames, but delayed content updates at fps / S and the grid jumps every S frames.

**Limits**
- One ring per effect. The pass name `ring` is fixed.
- After a change of source resolution, the atlas may hold undefined content for up to N frames.
- `FR_DEBUG_PATTERN` is a test hook (the pass writes a code of `frame_index` instead of the image). Do not use it in shipped effects.

## Known behaviour

- **The first frame after a filter is created is transparent.** The engine does not draw it, also for single-pass effects. It lasts one frame and is the same for the shipped effects (a stateless pixelate or blur shows it too). There is no fix yet.
- **Stacked face effects each run face tracking.** Two face filters on one source cost two tracker runs.

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
| `facetracking` | `texture2d` | face landmarks; binds `<name>_face_found`, `<name>_bbox_tl`, `<name>_bbox_br` (UV), `<name>_points_tex` (478x4: row 0 landmarks, rows 1-2 triangles, row 3 canonical UVs) and, with `"use_preraster": true`, `<name>_preraster_tex` (r = triangle id, g/b = barycentrics, a = inside). See "Face helpers". |
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
