// Retro Effects: Chromatic Aberration (ported from FiniteSingularity's obs-retro-effects, GPL-2.0)
// Manual (1): each channel is shifted by its offset (px) along its angle (degrees).
// Lens (2):   each channel is shifted radially, more towards the edges.

uniform int   ca_type;
uniform float ca_red_offset;
uniform float ca_red_offset_angle;
uniform float ca_green_offset;
uniform float ca_green_offset_angle;
uniform float ca_blue_offset;
uniform float ca_blue_offset_angle;

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

float2 manual_shift(float offset, float angle_deg)
{
    float a = angle_deg * 3.14159265358979 / 180.0;
    return float2(offset * cos(a), offset * sin(a));
}

float4 PSChromaticAberration(VertData v_in) : TARGET
{
    float2 coord = v_in.uv * uv_size;
    float2 shift_r;
    float2 shift_g;
    float2 shift_b;

    if (ca_type == 2) {
        // Lens: scale = 1 / half the diagonal, as in the C code.
        float scale = 1.0 / (sqrt(uv_size.x * uv_size.x + uv_size.y * uv_size.y) / 2.0);
        float2 dist = abs((coord - uv_size * 0.5) * scale);
        float2 from_center = v_in.uv - float2(0.5, 0.5);
        float len = length(from_center);
        float2 dir = len > 0.0 ? from_center / len : float2(0.0, 0.0);
        float2 diff = dist * dir;
        shift_r = ca_red_offset * diff;
        shift_g = ca_green_offset * diff;
        shift_b = ca_blue_offset * diff;
    } else {
        shift_r = manual_shift(ca_red_offset, ca_red_offset_angle);
        shift_g = manual_shift(ca_green_offset, ca_green_offset_angle);
        shift_b = manual_shift(ca_blue_offset, ca_blue_offset_angle);
    }

    float4 red   = image.Sample(textureSampler, (coord - shift_r) / uv_size);
    float4 green = image.Sample(textureSampler, (coord - shift_g) / uv_size);
    float4 blue  = image.Sample(textureSampler, (coord - shift_b) / uv_size);

    return float4(red.r, green.g, blue.b, red.a * 0.34 + green.a * 0.33 + blue.a * 0.33);
}

technique Draw { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSChromaticAberration(v_in); } }
