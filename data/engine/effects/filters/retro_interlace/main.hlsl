// Retro Effects: Interlace (ported from FiniteSingularity's obs-retro-effects, GPL-2.0)
// Every frame, alternate bands of rows take the new source frame; the other bands
// keep this filter's previous output (interlaced_prev), dimmed by the brightness reduction.

uniform int   interlace_thickness;
uniform float interlace_brightness_reduction;
uniform bool  interlace_reduce_alpha;

uniform float2 uv_size;
uniform texture2d interlaced_prev;

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

float4 PSInterlace(VertData v_in) : TARGET
{
    // The C filter flips its field counter before the first draw: 1, 0, 1, 0, ...
    float field = (frame_index % 2 == 0) ? 1.0 : 0.0;
    float thickness = max(float(interlace_thickness), 1.0);
    float br = 1.0 - interlace_brightness_reduction / 100.0;
    float4 reduction = float4(br, br, br, interlace_reduce_alpha ? br : 1.0);

    float2 coord = v_in.uv * uv_size;
    float cur_row = fmod(floor(coord.y / thickness) + field, 2.0);
    if (cur_row > 0.5) {
        return image.Sample(textureSampler, v_in.uv);
    }
    return interlaced_prev.Sample(textureSampler, v_in.uv) * reduction;
}

technique Draw { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSInterlace(v_in); } }
