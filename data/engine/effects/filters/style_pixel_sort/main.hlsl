// Pixel Sort: odd-even transposition sort along rows (or columns).
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

uniform texture2d start;
uniform texture2d sorted;

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
    return float4(c.rgb, m);
}

float4 PSSort(VertData v_in) : TARGET
{
    float2 axis = (direction == 0) ? float2(1.0, 0.0) : float2(0.0, 1.0);
    float len = (direction == 0) ? pass_size.x : pass_size.y;
    float pos = (direction == 0) ? v_in.uv.x * pass_size.x : v_in.uv.y * pass_size.y;
    float idx = floor(pos);

    float4 me;
    if (iteration == 0) me = start.Sample(pointSampler, v_in.uv);
    else                me = sorted.Sample(pointSampler, v_in.uv);

    // I am the left (first) element of a pair when idx + iteration is even
    float parity = fmod(idx + float(iteration), 2.0);
    bool isFirst = parity < 0.5;
    float pidx = isFirst ? idx + 1.0 : idx - 1.0;
    if (pidx < 0.0 || pidx >= len) return me;

    float2 puv = v_in.uv + axis * pass_texel * (isFirst ? 1.0 : -1.0);
    float4 other;
    if (iteration == 0) other = start.Sample(pointSampler, puv);
    else                other = sorted.Sample(pointSampler, puv);

    if (me.a < 0.5 || other.a < 0.5) return me;

    float lm = lum(me.rgb);
    float lo = lum(other.rgb);
    // first element should be the darker one (or the brighter one when reversed)
    bool firstWantsMe = reverse ? (lm >= lo) : (lm <= lo);
    if (isFirst) return firstWantsMe ? me : other;
    else         return firstWantsMe ? other : me;
}

float4 PSOut(VertData v_in) : TARGET
{
    float4 s = sorted.Sample(textureSampler, v_in.uv);
    float4 c = image.Sample(pointSampler, v_in.uv);
    return float4(s.rgb, c.a);
}

technique Start { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSStart(v_in); } }
technique Sort { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSSort(v_in); } }
technique Out  { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSOut(v_in); } }
