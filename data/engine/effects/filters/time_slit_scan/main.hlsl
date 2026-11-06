// Slit-Scan Time Warp (Silly Cam Filters)
// Each pixel reads the frame-ring (silly_framering.hlsl) at its own delay k = t * max_delay,
// where t runs 0..1 along rows, columns or radially from the centre.

#define FR_G 4
#define FR_N 16
#define FR_ATLAS_SCALE 1.0
#define FR_STRIDE 1
#define FR_BLEND
@include "silly_framering.hlsl"

uniform int   direction;
uniform float max_delay;
uniform bool  flip;

struct VertData {
    float2 uv  : TEXCOORD0;
    float4 pos : POSITION;
};

VertData VSDefault(VertData v_in)
{
    VertData vert_out;
    vert_out.uv  = v_in.uv;
    vert_out.pos = mul(float4(v_in.pos.xyz, 1.0), ViewProj);
    return vert_out;
}

float4 PSRing(VertData v_in) : TARGET
{
    return fr_ring_pixel(v_in.uv);
}

float4 PSOut(VertData v_in) : TARGET
{
    float2 uv = v_in.uv;
    float t = uv.y;
    if (direction == 1) {
        t = uv.x;
    }
    if (direction == 2) {
        float2 c = (uv - float2(0.5, 0.5)) * float2(1.0, vpixel / upixel);
        t = saturate(length(c) / 0.5);
    }
    if (flip) {
        t = 1.0 - t;
    }
    float k = t * min(max_delay, 15.0);
    return fr_sample(uv, k);
}

technique Ring { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSRing(v_in); } }
technique Draw { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSOut(v_in); } }
