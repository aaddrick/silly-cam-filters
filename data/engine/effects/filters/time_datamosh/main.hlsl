// Datamosh (Silly Cam Filters)
// Pass "mv": block matching, one vector per 8x8 block (pass at 1/8 size). The vector (in source
//            pixels) points to where the block's content was in the previous frame.
// Pass "mosh": output = previous output fetched along that vector (so moving parts drag old picture),
//            plus a small leak toward the live source. A forced keyframe (periodic, or the
//            "Drop keyframe now" switch) resets the output to the source.

uniform bool  smear;
uniform int   block_size;
uniform float refresh_interval;
uniform float leak;
uniform bool  drop_keyframe;

uniform texture2d image_prev;
uniform texture2d mosh_prev;
uniform texture2d mv;

sampler_state textureSampler {
    Filter    = Linear;
    AddressU  = Clamp;
    AddressV  = Clamp;
};
sampler_state pointSampler {
    Filter    = Point;
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

float luma(float3 c) { return dot(c, float3(0.299, 0.587, 0.114)); }

float block_sad(float2 uv, float2 o, float2 px)
{
    float sad = 0.0;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            float2 s = float2(i, j) * 3.0 * px;
            float a = luma(image.Sample(textureSampler, uv + s).rgb);
            float b = luma(image_prev.Sample(textureSampler, uv + s + o * px).rgb);
            sad += abs(a - b);
        }
    }
    return sad;
}

float4 PSMotion(VertData v_in) : TARGET
{
    float2 uv = v_in.uv;
    float2 px = float2(upixel, vpixel);
    float zero_sad = block_sad(uv, float2(0.0, 0.0), px);
    float best = zero_sad;
    float2 bo = float2(0.0, 0.0);
    // Only search when the block really changed (keeps still areas exactly still).
    if (zero_sad > 0.12) {
        for (int j = -4; j <= 4; j++) {
            for (int i = -4; i <= 4; i++) {
                float2 o = float2(i, j) * 3.0;
                float s = block_sad(uv, o, px) + 0.004 * length(o);
                if (s < best) { best = s; bo = o; }
            }
        }
        if (best > zero_sad * 0.7) { bo = float2(0.0, 0.0); }
    }
    return float4(bo, zero_sad, 1.0);
}

float4 PSMosh(VertData v_in) : TARGET
{
    float2 uv = v_in.uv;
    float2 px = float2(upixel, vpixel);
    float4 src = image.Sample(textureSampler, uv);
    if (!smear) { return src; }

    // Forced keyframe: first frame, every refresh_interval seconds, or the switch.
    float ri = max(refresh_interval, 0.5);
    bool key = (frame_index < 2)
        || (floor(time / ri) != floor((time - delta_time) / ri))
        || drop_keyframe;
    float4 prev0 = mosh_prev.Sample(pointSampler, uv);
    if (key || prev0.a < 0.5) { return float4(src.rgb, 1.0); }

    // One vector per block group (block_size blocks of 8 px).
    float2 ncell = float2(1.0, 1.0) / (px * 8.0);
    float k = max(float(block_size), 1.0);
    float2 cell = floor(uv * ncell);
    float2 grp = floor(cell / k) * k + (k - 1.0) * 0.5;
    float2 mvuv = (grp + 0.5) / ncell;
    float4 v = mv.Sample(pointSampler, mvuv);
    float2 o = v.xy;

    float4 pushed = mosh_prev.Sample(textureSampler, uv + o * px);
    bool moving = dot(o, o) > 0.5;
    // Moving blocks keep a small leak so the smear stays alive but bounded; still blocks recover slowly.
    float l = moving ? 0.0 : leak;
    float3 col = lerp(pushed.rgb, src.rgb, l);
    return float4(col, 1.0);
}

technique Motion { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSMotion(v_in); } }
technique Mosh   { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSMosh(v_in); } }
