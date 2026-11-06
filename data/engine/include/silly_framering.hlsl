// silly_framering.hlsl - frame ring: "what did the image look like k frames ago?"
// Part of Silly Cam Filters. See docs/ENGINE.md, "Frame ring".
//
// Use (effect main.hlsl):
//     #define FR_G 3                 // atlas is G x G cells
//     #define FR_N 9                 // slots used, 2..G*G   (default G*G)
//     #define FR_ATLAS_SCALE 1.0     // must equal the "scale" of the ring pass in meta.json (default 1.0)
//     #define FR_STRIDE 1            // store every STRIDE-th frame (default 1)
//     // #define FR_BLEND            // optional: fractional k blends two stored frames (default: nearest)
//     @include "silly_framering.hlsl"
// meta.json: a pass named exactly "ring" (technique "Ring" or any name that calls fr_ring_pixel),
//     "scale": FR_ATLAS_SCALE, no "iterations", default format. Later passes read the atlas through
//     fr_sample(). The technique for the ring pass is declared by the effect:
//         float4 PSRing(VertData v_in) : TARGET { return fr_ring_pixel(v_in.uv); }
//
// The ring pass reads its own name ("ring") = its previous-frame output, so no ring_prev is needed.
// frame_index (engine) is the write cursor; it restarts at 0 on show/reload, which also restarts the
// valid-frame count, so stale slots are never read.

#ifndef FR_G
#define FR_G 3
#endif
#ifndef FR_N
#define FR_N (FR_G * FR_G)
#endif
#ifndef FR_ATLAS_SCALE
#define FR_ATLAS_SCALE 1.0
#endif
#ifndef FR_STRIDE
#define FR_STRIDE 1
#endif

uniform texture2d ring;

sampler_state fr_point {
    Filter   = Point;
    AddressU = Clamp;
    AddressV = Clamp;
};
sampler_state fr_linear {
    Filter   = Linear;
    AddressU = Clamp;
    AddressV = Clamp;
};

// ---- ring pass ------------------------------------------------------------------------------------

// Pixel shader body of the ring pass. uv = the pass's v_in.uv (0..1 over the whole atlas).
float4 fr_ring_pixel(float2 uv)
{
    float2 g    = uv * float(FR_G);
    int    col  = clamp(int(floor(g.x)), 0, FR_G - 1);
    int    row  = clamp(int(floor(g.y)), 0, FR_G - 1);
    int    slot = row * FR_G + col;

    if (slot >= FR_N) {
        return float4(0.0, 0.0, 0.0, 0.0);
    }

    int  write_slot = (frame_index / FR_STRIDE) % FR_N;
    bool writing    = (frame_index % FR_STRIDE) == 0 && slot == write_slot;

    if (writing) {
#ifdef FR_DEBUG_PATTERN
        // Test hook (not for shipped effects): the effect declares `uniform bool fr_pattern_on;`.
        // The slot is filled with a code of frame_index instead of the image: red = (f % 16) * 16,
        // green = ((f / 16) % 16) * 16, so a reader can check slot k holds frame f-k exactly.
        if (fr_pattern_on) {
            return float4(float(frame_index % 16) * (16.0 / 255.0), float((frame_index / 16) % 16) * (16.0 / 255.0), 0.0, 1.0);
        }
#endif
        // 4-tap box prefilter of the source into the cell (D = source pixels per cell pixel).
        float2 local = g - float2(float(col), float(row));
        float  d     = float(FR_G) / FR_ATLAS_SCALE;
        float2 o     = float2(upixel, vpixel) * (d * 0.25);
        float4 c = image.Sample(fr_linear, local + float2(-o.x, -o.y))
                 + image.Sample(fr_linear, local + float2( o.x, -o.y))
                 + image.Sample(fr_linear, local + float2(-o.x,  o.y))
                 + image.Sample(fr_linear, local + float2( o.x,  o.y));
        return c * 0.25;
    }
    // Copy-through: point sample at this very texel (same size as the previous frame) = exact copy.
    return ring.Sample(fr_point, uv);
}

// ---- reading --------------------------------------------------------------------------------------

// Number of stored frames that are valid now (1 on the first frame, up to FR_N): FR_COUNT.
// Largest delay, in frames, that the ring can answer now (0 on the first frame): FR_MAX_K.
// They are object-like macros over a function taking frame_index: the engine HLSL parser rejects
// zero-argument calls and function-like macros.
int fr_count_of(int f)
{
    return min(f / FR_STRIDE + 1, FR_N);
}

float fr_max_k_of(int f)
{
    return float((f % FR_STRIDE) + (fr_count_of(f) - 1) * FR_STRIDE);
}

#define FR_COUNT fr_count_of(frame_index)
#define FR_MAX_K fr_max_k_of(frame_index)

float fr_clamp_k(float k)
{
    return clamp(k, 0.0, FR_MAX_K);
}

bool fr_has(float k)
{
    return k <= FR_MAX_K;
}

// image uv (0..1) -> atlas uv inside a slot, inset by half a cell texel.
float2 fr_atlas_uv(float2 uv, int slot)
{
    int    col = slot % FR_G;
    int    row = slot / FR_G;
    float2 h   = float2(upixel, vpixel) * (0.5 * float(FR_G) / FR_ATLAS_SCALE);
    float2 l   = clamp(uv, h, float2(1.0, 1.0) - h);
    return (l + float2(float(col), float(row))) / float(FR_G);
}

// The j-th stored frame back (j = 0 newest), exact, one tap. j is clamped to 0..FR_COUNT-1.
float4 fr_sample_i(float2 uv, int j)
{
    int jj   = clamp(j, 0, FR_COUNT - 1);
    int slot = (frame_index / FR_STRIDE - jj) % FR_N;
    return ring.Sample(fr_linear, fr_atlas_uv(uv, slot));
}

// The frame k frames ago at image uv. k is clamped to 0..FR_MAX_K.
// Default: the nearest stored frame (exact for FR_STRIDE 1 and whole k). With FR_BLEND, fractional k
// (and FR_STRIDE > 1) blends the two neighbouring stored frames.
float4 fr_sample(float2 uv, float k)
{
    float j = max(fr_clamp_k(k) - float(frame_index % FR_STRIDE), 0.0) / float(FR_STRIDE);
#ifdef FR_BLEND
    int   j0 = int(floor(j));
    float t  = j - float(j0);
    float4 a = fr_sample_i(uv, j0);
    if (t < 0.001) {
        return a;
    }
    return lerp(a, fr_sample_i(uv, j0 + 1), t);
#else
    return fr_sample_i(uv, int(floor(j + 0.5)));
#endif
}
