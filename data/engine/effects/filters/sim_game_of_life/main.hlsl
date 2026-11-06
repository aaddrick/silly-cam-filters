// Game of Life: Conway's rules on a 384x216 grid kept in an rgba32f state pass.
// State per texel: r = alive (0/1), g = age 0..1 (0 = newborn), b = last tick, a = 1 + restart epoch (0 = not started).
// With cell_size k, one logical cell is k x k texels; every texel of a block computes the same result.

uniform int cell_size;
uniform float seed_threshold;
uniform bool seed_dark;
uniform float inject;
uniform int step_every;
uniform float restart_seconds;
uniform float4 overlay_color;
uniform float overlay_strength;
uniform bool test_pattern;

uniform texture2d life_prev;
uniform texture2d life;

uniform float2 pass_size;

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

uniform texture2d meanl;

// Frame mean luma, from a 1x1 pass that averages an 8x8 grid of taps (thresholds are relative to it).
float4 PSMean(VertData v_in) : TARGET
{
    float acc = 0.0;
    for (int j = 0; j < 8; j++) {
        for (int i = 0; i < 8; i++) {
            float2 p = (float2(float(i), float(j)) + 0.5) / 8.0 + (v_in.uv - 0.5) * 1e-5;
            acc += dot(image.Sample(textureSampler, p).rgb, float3(0.299, 0.587, 0.114));
        }
    }
    return float4(acc / 64.0, 0.0, 0.0, 1.0);
}

// Luma relative to the frame mean: the mean maps to 0.5, so one threshold works on dim and bright footage.
float rel_luma(float3 rgb)
{
    float m = meanl.Sample(pointSampler, float2(0.5, 0.5)).r;
    return saturate(0.5 + (dot(rgb, float3(0.299, 0.587, 0.114)) - m) * 1.5);
}

float hash21(float2 p, float s)
{
    float3 p3 = frac(float3(p.x, p.y, s) * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return frac((p3.x + p3.y) * p3.z);
}

float mask_at(float2 uvc)
{
    float lum = rel_luma(image.Sample(textureSampler, uvc).rgb);
    return seed_dark ? (lum < seed_threshold ? 1.0 : 0.0) : (lum > seed_threshold ? 1.0 : 0.0);
}

float is_cell(float2 c, float2 p)
{
    return (abs(c.x - p.x) < 0.5 && abs(c.y - p.y) < 0.5) ? 1.0 : 0.0;
}

float pattern_alive(float2 c)
{
    float a = 0.0;
    // blinker
    a += is_cell(c, float2(5, 5)) + is_cell(c, float2(6, 5)) + is_cell(c, float2(7, 5));
    // glider (moves down and right)
    a += is_cell(c, float2(21, 10)) + is_cell(c, float2(22, 11)) + is_cell(c, float2(20, 12))
       + is_cell(c, float2(21, 12)) + is_cell(c, float2(22, 12));
    return saturate(a);
}

float4 PSLife(VertData v_in) : TARGET
{
    float k = float(max(cell_size, 1));
    float2 t = floor(v_in.uv * pass_size);
    float2 ncell = floor(pass_size / k);
    float2 c = floor(t / k);
    float2 uvc = (c * k + k * 0.5) / pass_size;

    float4 prev = life_prev.Sample(pointSampler, uvc);

    float tick = floor(float(frame_index) / float(max(step_every, 1)));
    float epoch = (restart_seconds > 0.5) ? floor(float(frame_index) / (restart_seconds * 30.0)) : 0.0;
    bool fresh = prev.a < 0.5 || (prev.a - 1.0) != epoch;

    // Texels outside the logical grid stay dead.
    if (c.x >= ncell.x || c.y >= ncell.y)
        return float4(0.0, 1.0, tick, 1.0 + epoch);

    if (fresh) {
        float alive;
        if (test_pattern) {
            alive = pattern_alive(c);
        } else {
            alive = mask_at(uvc) * (hash21(c, epoch + 1.7) < 0.45 ? 1.0 : 0.0);
        }
        return float4(alive, 0.0, tick, 1.0 + epoch);
    }

    // Wait for the next tick; keep the state as it is.
    if (prev.b == tick)
        return float4(prev.r, prev.g, prev.b, prev.a);

    float n = 0.0;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            float2 nc = c + float2(i, j);
            float inb = (nc.x >= 0.0 && nc.y >= 0.0 && nc.x < ncell.x && nc.y < ncell.y && (i != 0 || j != 0)) ? 1.0 : 0.0;
            float2 uvn = (clamp(nc, float2(0.0, 0.0), ncell - 1.0) * k + k * 0.5) / pass_size;
            n += inb * step(0.5, life_prev.Sample(pointSampler, uvn).r);
        }
    }
    bool was = prev.r > 0.5;
    bool now = was ? (n > 1.5 && n < 3.5) : (n > 2.5 && n < 3.5);

    if (!now && !test_pattern && inject > 0.0 && mask_at(uvc) > 0.5 && hash21(c, tick) < inject)
        now = true;

    float age = now ? (was ? min(prev.g + 0.1, 1.0) : 0.0) : 1.0;
    return float4(now ? 1.0 : 0.0, age, tick, prev.a);
}

float4 PSDraw(VertData v_in) : TARGET
{
    float4 base = image.Sample(textureSampler, v_in.uv);
    float k = float(max(cell_size, 1));
    float2 g = v_in.uv * pass_size;
    float2 c = floor(floor(g) / k);
    float2 f = frac(g / k);
    float2 uvc = (c * k + k * 0.5) / pass_size;
    float4 s = life.Sample(pointSampler, uvc);

    float2 gap = float2(0.14, 0.14);
    float2 inside = step(gap, f) * step(f, 1.0 - gap);
    float box = (k > 1.5) ? inside.x * inside.y : 1.0;

    float live = step(0.5, s.r) * box;
    float3 col = lerp(lerp(overlay_color.rgb, float3(1.0, 1.0, 1.0), 0.5), overlay_color.rgb, saturate(s.g * 3.0));
    float3 rgb = lerp(base.rgb, col, live * overlay_strength);
    return float4(rgb, base.a);
}

technique Life { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSLife(v_in); } }
technique Draw { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSDraw(v_in); } }
technique Mean { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSMean(v_in); } }
