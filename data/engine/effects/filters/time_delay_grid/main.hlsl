// Delay Grid (Silly Cam Filters)
// Cell i (row-major, top-left = 0) shows the frame delay_step * i frames ago, from the frame ring.
// Ring: 5x5 slots (N = 25), atlas scale 5/3 so each stored cell is 640x360 at 1080p. Max delay 8*3 = 24.

#define FR_G 5
#define FR_N 25
#define FR_ATLAS_SCALE 1.6667
#define FR_STRIDE 1
@include "silly_framering.hlsl"

uniform int   grid_size;
uniform int   delay_step;
uniform float gap;

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
    float gs = float(max(grid_size, 2));
    float2 g = v_in.uv * gs;
    float2 cell = floor(g);
    float2 local = g - cell;
    int idx = int(cell.y) * grid_size + int(cell.x);
    float k = float(idx * max(delay_step, 1));

    // Gap lines between cells (in cell-local units).
    float gl = gap * gs;
    if (local.x < gl * 0.5 || local.x > 1.0 - gl * 0.5 || local.y < gl * 0.5 || local.y > 1.0 - gl * 0.5) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }
    if (idx == 0) {
        return image.Sample(fr_linear, local);
    }
    return fr_sample(local, k);
}

technique Ring { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSRing(v_in); } }
technique Draw { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSOut(v_in); } }
