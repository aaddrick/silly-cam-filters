// Pixel Sort (6 chained sort passes of 64 steps, since the engine caps iterations at 64): odd-even transposition sort along rows (or columns).
//   (start and sorted run at half size: spans are twice as long per step and it is 4x cheaper)
//   start:   copy the picture; alpha marks the pixels whose brightness is inside [lum_low, lum_high]
//   sorted: one compare-exchange step per iteration between neighbours that are both marked.
//           After N steps a span is sorted if it is no longer than N pixels.
//   result: the sorted picture with the original alpha

uniform float lum_low;
uniform float lum_high;
uniform int sort_steps;
uniform int direction;
uniform bool reverse;
uniform bool protect_skin;

uniform texture2d start;
uniform texture2d sort0;
uniform texture2d sort1;
uniform texture2d sort2;
uniform texture2d sort3;
uniform texture2d sort4;
uniform texture2d sort5;

uniform float2 pass_size;
uniform float2 pass_texel;
uniform int iteration;

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

float lum(float3 c)
{
    return dot(c, float3(0.299, 0.587, 0.114));
}

float4 PSStart(VertData v_in) : TARGET
{
    float4 c = image.Sample(textureSampler, v_in.uv);
    float l = lum(c.rgb);
    // thresholds are relative to the frame's own brightness range (8x8 grid min/max),
    // so dim webcams and darker skin get streaks too
    float mn = 1.0;
    float mx = 0.0;
    for (int j = 0; j < 8; j++) {
        for (int i = 0; i < 8; i++) {
            float lg = lum(image.Sample(textureSampler, (float2(float(i), float(j)) + 0.5) / 8.0).rgb);
            mn = min(mn, lg);
            mx = max(mx, lg);
        }
    }
    float rng = max(mx - mn, 0.05);
    float lo = mn + lum_low * rng;
    float hi = mn + lum_high * rng;
    float m = (l >= lo && l <= hi) ? 1.0 : 0.0;
    // skin-like colours (warm, r > g > b, not saturated orange) are never sorted, so faces stay readable
    float3 q = c.rgb;
    bool skin = (q.r > q.b + 0.02) && (q.r >= q.g) && (q.g >= q.b * 0.9) && ((q.r - q.g) < 0.3) && (q.r > 0.05);
    if (protect_skin && skin) m = 0.0;
    return float4(c.rgb, m);
}

float4 SortStep(float2 uv, float4 me, float4 other_fwd, float4 other_bwd, int g, float idx, float len)
{
    // I am the left (first) element of a pair when idx + g is even
    float parity = fmod(idx + float(g), 2.0);
    bool isFirst = parity < 0.5;
    float pidx = isFirst ? idx + 1.0 : idx - 1.0;
    if (g >= sort_steps || pidx < 0.0 || pidx >= len) return me;
    float4 other = isFirst ? other_fwd : other_bwd;
    if (me.a < 0.5 || other.a < 0.5) return me;
    float lm = lum(me.rgb);
    float lo = lum(other.rgb);
    bool firstWantsMe = reverse ? (lm >= lo) : (lm <= lo);
    if (isFirst) return firstWantsMe ? me : other;
    else         return firstWantsMe ? other : me;
}

float4 PSSort0(VertData v_in) : TARGET
{
    float2 axis = (direction == 0) ? float2(1.0, 0.0) : float2(0.0, 1.0);
    float len = (direction == 0) ? pass_size.x : pass_size.y;
    float idx = floor((direction == 0) ? v_in.uv.x * pass_size.x : v_in.uv.y * pass_size.y);
    float2 d = axis * pass_texel;
    float4 me; float4 f; float4 b;
    if (iteration == 0) {
        me = start.Sample(pointSampler, v_in.uv);
        f = start.Sample(pointSampler, v_in.uv + d);
        b = start.Sample(pointSampler, v_in.uv - d);
    } else {
        me = sort0.Sample(pointSampler, v_in.uv);
        f = sort0.Sample(pointSampler, v_in.uv + d);
        b = sort0.Sample(pointSampler, v_in.uv - d);
    }
    return SortStep(v_in.uv, me, f, b, 0 + iteration, idx, len);
}

float4 PSSort1(VertData v_in) : TARGET
{
    float2 axis = (direction == 0) ? float2(1.0, 0.0) : float2(0.0, 1.0);
    float len = (direction == 0) ? pass_size.x : pass_size.y;
    float idx = floor((direction == 0) ? v_in.uv.x * pass_size.x : v_in.uv.y * pass_size.y);
    float2 d = axis * pass_texel;
    float4 me; float4 f; float4 b;
    if (iteration == 0) {
        me = sort0.Sample(pointSampler, v_in.uv);
        f = sort0.Sample(pointSampler, v_in.uv + d);
        b = sort0.Sample(pointSampler, v_in.uv - d);
    } else {
        me = sort1.Sample(pointSampler, v_in.uv);
        f = sort1.Sample(pointSampler, v_in.uv + d);
        b = sort1.Sample(pointSampler, v_in.uv - d);
    }
    return SortStep(v_in.uv, me, f, b, 64 + iteration, idx, len);
}

float4 PSSort2(VertData v_in) : TARGET
{
    float2 axis = (direction == 0) ? float2(1.0, 0.0) : float2(0.0, 1.0);
    float len = (direction == 0) ? pass_size.x : pass_size.y;
    float idx = floor((direction == 0) ? v_in.uv.x * pass_size.x : v_in.uv.y * pass_size.y);
    float2 d = axis * pass_texel;
    float4 me; float4 f; float4 b;
    if (iteration == 0) {
        me = sort1.Sample(pointSampler, v_in.uv);
        f = sort1.Sample(pointSampler, v_in.uv + d);
        b = sort1.Sample(pointSampler, v_in.uv - d);
    } else {
        me = sort2.Sample(pointSampler, v_in.uv);
        f = sort2.Sample(pointSampler, v_in.uv + d);
        b = sort2.Sample(pointSampler, v_in.uv - d);
    }
    return SortStep(v_in.uv, me, f, b, 128 + iteration, idx, len);
}

float4 PSSort3(VertData v_in) : TARGET
{
    float2 axis = (direction == 0) ? float2(1.0, 0.0) : float2(0.0, 1.0);
    float len = (direction == 0) ? pass_size.x : pass_size.y;
    float idx = floor((direction == 0) ? v_in.uv.x * pass_size.x : v_in.uv.y * pass_size.y);
    float2 d = axis * pass_texel;
    float4 me; float4 f; float4 b;
    if (iteration == 0) {
        me = sort2.Sample(pointSampler, v_in.uv);
        f = sort2.Sample(pointSampler, v_in.uv + d);
        b = sort2.Sample(pointSampler, v_in.uv - d);
    } else {
        me = sort3.Sample(pointSampler, v_in.uv);
        f = sort3.Sample(pointSampler, v_in.uv + d);
        b = sort3.Sample(pointSampler, v_in.uv - d);
    }
    return SortStep(v_in.uv, me, f, b, 192 + iteration, idx, len);
}

float4 PSSort4(VertData v_in) : TARGET
{
    float2 axis = (direction == 0) ? float2(1.0, 0.0) : float2(0.0, 1.0);
    float len = (direction == 0) ? pass_size.x : pass_size.y;
    float idx = floor((direction == 0) ? v_in.uv.x * pass_size.x : v_in.uv.y * pass_size.y);
    float2 d = axis * pass_texel;
    float4 me; float4 f; float4 b;
    if (iteration == 0) {
        me = sort3.Sample(pointSampler, v_in.uv);
        f = sort3.Sample(pointSampler, v_in.uv + d);
        b = sort3.Sample(pointSampler, v_in.uv - d);
    } else {
        me = sort4.Sample(pointSampler, v_in.uv);
        f = sort4.Sample(pointSampler, v_in.uv + d);
        b = sort4.Sample(pointSampler, v_in.uv - d);
    }
    return SortStep(v_in.uv, me, f, b, 256 + iteration, idx, len);
}

float4 PSSort5(VertData v_in) : TARGET
{
    float2 axis = (direction == 0) ? float2(1.0, 0.0) : float2(0.0, 1.0);
    float len = (direction == 0) ? pass_size.x : pass_size.y;
    float idx = floor((direction == 0) ? v_in.uv.x * pass_size.x : v_in.uv.y * pass_size.y);
    float2 d = axis * pass_texel;
    float4 me; float4 f; float4 b;
    if (iteration == 0) {
        me = sort4.Sample(pointSampler, v_in.uv);
        f = sort4.Sample(pointSampler, v_in.uv + d);
        b = sort4.Sample(pointSampler, v_in.uv - d);
    } else {
        me = sort5.Sample(pointSampler, v_in.uv);
        f = sort5.Sample(pointSampler, v_in.uv + d);
        b = sort5.Sample(pointSampler, v_in.uv - d);
    }
    return SortStep(v_in.uv, me, f, b, 320 + iteration, idx, len);
}

float4 PSOut(VertData v_in) : TARGET
{
    float4 s = sort5.Sample(textureSampler, v_in.uv);
    float4 c = image.Sample(pointSampler, v_in.uv);
    return float4(s.rgb, c.a);
}

technique Start { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSStart(v_in); } }
technique Sort0 { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSSort0(v_in); } }
technique Sort1 { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSSort1(v_in); } }
technique Sort2 { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSSort2(v_in); } }
technique Sort3 { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSSort3(v_in); } }
technique Sort4 { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSSort4(v_in); } }
technique Sort5 { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSSort5(v_in); } }
technique Out  { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSOut(v_in); } }
