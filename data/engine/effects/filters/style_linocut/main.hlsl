// Paper Cutout: brightness is cut into `levels` flat tones (ink -> middle -> paper),
// a Sobel outline is printed in ink, and a procedural paper grain breaks up the
// tone borders (so the tones stay a fixed palette; the grain only moves the cuts).

uniform int levels;
uniform float edge_strength;
uniform float edge_width;
uniform float grain;
uniform float auto_tone;
uniform texture2d avg;
uniform float4 ink_color;
uniform float4 mid_color;
uniform float4 paper_color;

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

float lum(float3 c)
{
    return dot(c, float3(0.299, 0.587, 0.114));
}

float hash21(float2 p)
{
    p = frac(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return frac(p.x * p.y);
}

float vnoise(float2 p)
{
    float2 i = floor(p);
    float2 f = frac(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    return lerp(lerp(a, b, f.x), lerp(c, d, f.x), f.y);
}

// Local average brightness on a coarse 16x9 grid (6x6 taps per cell), so dark rooms
// and darker skin still get all the tones: the cut uses brightness relative to this.
float4 PSAvg(VertData v_in) : TARGET
{
    float2 cell = float2(1.0 / 16.0, 1.0 / 9.0);
    float acc = 0.0;
    for (int j = 0; j < 6; j++) {
        for (int i = 0; i < 6; i++) {
            float2 o = (float2(float(i), float(j)) + 0.5) / 6.0 - 0.5;
            acc += lum(image.Sample(textureSampler, v_in.uv + o * cell).rgb);
        }
    }
    return float4(acc / 36.0, 0.0, 0.0, 1.0);
}

float4 PSCutout(VertData v_in) : TARGET
{
    float2 px = float2(upixel, vpixel);
    float2 d = px * edge_width;

    float l00 = lum(image.Sample(textureSampler, v_in.uv + float2(-d.x, -d.y)).rgb);
    float l10 = lum(image.Sample(textureSampler, v_in.uv + float2(0.0, -d.y)).rgb);
    float l20 = lum(image.Sample(textureSampler, v_in.uv + float2(d.x, -d.y)).rgb);
    float l01 = lum(image.Sample(textureSampler, v_in.uv + float2(-d.x, 0.0)).rgb);
    float4 cc = image.Sample(textureSampler, v_in.uv);
    float l11 = lum(cc.rgb);
    float l21 = lum(image.Sample(textureSampler, v_in.uv + float2(d.x, 0.0)).rgb);
    float l02 = lum(image.Sample(textureSampler, v_in.uv + float2(-d.x, d.y)).rgb);
    float l12 = lum(image.Sample(textureSampler, v_in.uv + float2(0.0, d.y)).rgb);
    float l22 = lum(image.Sample(textureSampler, v_in.uv + float2(d.x, d.y)).rgb);
    float gx = (l20 + 2.0 * l21 + l22) - (l00 + 2.0 * l01 + l02);
    float gy = (l02 + 2.0 * l12 + l22) - (l00 + 2.0 * l10 + l20);
    float edge = smoothstep(0.25, 0.6, sqrt(gx * gx + gy * gy)) * edge_strength;

    // paper grain: a few octaves of value noise in pixel space
    float2 pp = v_in.uv / px;
    float n = vnoise(pp * 0.5) * 0.5 + vnoise(pp * 0.17 + 7.3) * 0.35 + hash21(floor(pp)) * 0.15;

    float mean = avg.Sample(textureSampler, v_in.uv).r;
    float rel = l11 / (l11 + 1.4 * max(mean, 0.05));
    float base = lerp(l11, rel, auto_tone);
    float x = base + (n - 0.5) * grain * (1.0 / float(levels)) * 1.0;
    float lv = clamp(floor(x * float(levels)), 0.0, float(levels - 1));
    float t = lv / float(levels - 1);

    float3 tone = (t < 0.5) ? lerp(ink_color.rgb, mid_color.rgb, t * 2.0)
                            : lerp(mid_color.rgb, paper_color.rgb, t * 2.0 - 1.0);
    float3 col = lerp(tone, ink_color.rgb, edge);
    return float4(col, cc.a);
}

technique Avg  { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSAvg(v_in); } }
technique Draw { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSCutout(v_in); } }
