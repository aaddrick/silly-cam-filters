// Retro: Cathode Boot. Port of the Cathode Boot filter from obs-retro-effects 1.0.2 by
// FiniteSingularity (GPL-2.0, https://github.com/FiniteSingularity/obs-retro-effects).
// Progress 0% shows the picture, 100% shows the background (the tube is off). The picture
// first collapses to a horizontal line, then to a dot, then fades out.
//
// New in this port: cathode_boot_auto plays the animation from `time` (seconds since the
// filter became visible) instead of reading the Progress slider.

uniform float cathode_boot_progress;          // %
uniform int   cathode_boot_auto;              // 0 manual, 1 power on, 2 power off
uniform float cathode_boot_duration;          // s
uniform float cathode_boot_delay;             // s
uniform float cathode_boot_vert_thickness;    // px
uniform float cathode_boot_horiz_thickness;   // px
uniform float cathode_boot_glow_size;         // px
uniform float4 cathode_boot_glow_color;
uniform float4 cathode_boot_bg_color;
uniform float cathode_boot_vert_start;        // %
uniform float cathode_boot_vert_end;          // %
uniform float cathode_boot_horiz_start;       // %
uniform float cathode_boot_horiz_end;         // %
uniform float cathode_boot_fade_start;        // %
uniform float cathode_boot_fade_end;          // %

uniform float2 uv_size;

sampler_state textureSampler {
    Filter    = Linear;
    AddressU  = Clamp;
    AddressV  = Clamp;
};

struct VertData {
    float4 pos : POSITION;
    float2 uv  : TEXCOORD0;
};

VertData VSDefault(VertData v_in)
{
    VertData vert_out;
    vert_out.pos = mul(float4(v_in.pos.xyz, 1.0), ViewProj);
    vert_out.uv  = v_in.uv;
    return vert_out;
}

float SDF(float2 coord, float2 dims)
{
    float2 dist = abs(coord) - dims;
    return min(max(dist.x, dist.y), 0.0) + length(max(dist, float2(0.0, 0.0)));
}

// saturate((p - a) / (b - a)) that does not divide by zero when a == b
float ramp(float p, float a, float b)
{
    float r = b - a;
    if (abs(r) < 1.e-5) {
        return p >= a ? 1.0 : 0.0;
    }
    return saturate((p - a) / r);
}

float4 PSEffect(VertData v_in) : TARGET
{
    float progress = cathode_boot_progress / 100.0;
    if (cathode_boot_auto != 0) {
        float t = saturate((time - cathode_boot_delay) / max(cathode_boot_duration, 0.001));
        progress = cathode_boot_auto == 1 ? 1.0 - t : t;
    }

    float2 vert_range  = float2(cathode_boot_vert_start,  cathode_boot_vert_end)  / 100.0;
    float2 horiz_range = float2(cathode_boot_horiz_start, cathode_boot_horiz_end) / 100.0;
    float2 fade_range  = float2(cathode_boot_fade_start,  cathode_boot_fade_end)  / 100.0;
    float2 thickness = float2(cathode_boot_horiz_thickness / uv_size.x, cathode_boot_vert_thickness / uv_size.y);

    // 0,0 is the center of the frame
    float2 d = v_in.uv - float2(0.5, 0.5);

    // How far into the collapse we are
    float2 progress_norm = float2(ramp(progress, horiz_range.x, horiz_range.y), ramp(progress, vert_range.x, vert_range.y));
    // How far into the fade we are
    float progress_fade = ramp(progress, fade_range.x, fade_range.y);

    float2 scale = progress_norm * (thickness - float2(1.0, 1.0)) + float2(1.0, 1.0);
    float2 px_scale = floor(scale * uv_size);
    scale = max(px_scale, float2(1.0, 1.0)) / uv_size;

    float2 px_coord = floor(d * uv_size);
    d /= scale;

    float sdf_val = SDF(px_coord * 2.0, px_scale);

    float2 uv = float2(0.5, 0.5) + d;
    bool inside = sdf_val <= 0.0;

    float4 color = image.Sample(textureSampler, uv);
    color = lerp(color, cathode_boot_glow_color, max(progress_norm.x, progress_norm.y));

    float4 glow = saturate(lerp(cathode_boot_bg_color, cathode_boot_glow_color, 1.0 - max(sdf_val, 0.0) / cathode_boot_glow_size));

    float4 c = inside ? color : glow;
    return c * (1.0 - progress_fade) + progress_fade * cathode_boot_bg_color;
}

technique Draw { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSEffect(v_in); } }
