// Reaction-Diffusion Skin: Gray-Scott on a 384x216 rgba32f grid.
// State: r = U (food), g = V (the pattern), b = reach (1 on a seeding edge, falling 1/REACH per texel away), a = 1 once started.
// Clock: a 1x1 rgba32f pass kept across frames (clock_prev): r = 1 on a restart frame, g = frames since restart,
// b = `time` at restart, a = 1 + rand_seed (stamp of this filter instance; anything else = not started).
// A restart fires when frames >= restart_seconds*30 OR wall seconds >= restart_seconds (counted, never an exact frame_index test),
// so skipped frame numbers, slow renderers and stale textures from another filter all still restart.
// U' = U + Du*lap(U) - U*V*V + F*(1-U);  V' = V + Dv*lap(V) + U*V*V - (F+k)*V;  Du = 1, Dv = 0.5, dt = 1.
// Camera edges inject V; the picture's brightness shifts F a little so the pattern follows you.
// Every value is clamped to 0..1.

uniform int preset;
uniform int rd_iterations;
uniform float seed_edges;
uniform float follow;
uniform float mix_amount;
uniform float4 pattern_color;
uniform float restart_seconds;
uniform bool reset;
uniform bool show_chemical;

uniform texture2d rd;
uniform texture2d rd_prev;
uniform texture2d clock;
uniform texture2d clock_prev;

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

// Restart clock (see header). One texel; every rd texel reads the same decision.
float4 PSClock(VertData v_in) : TARGET
{
    float4 c = clock_prev.Sample(pointSampler, float2(0.5, 0.5) + (v_in.uv - 0.5) * 1e-5);
    bool started = c.a > 0.5 && abs(c.a - 1.0 - rand_seed) < 0.0001;
    float frames = c.g + 1.0;
    float secs = time - c.b;
    bool restart = !started || reset;
    if (restart_seconds > 0.5)
        restart = restart || frames >= restart_seconds * 30.0 || secs >= restart_seconds || secs < -0.5;
    if (restart)
        return float4(1.0, 0.0, time, 1.0 + rand_seed);
    return float4(0.0, frames, c.b, c.a);
}

// Fraction of the restart period that has passed (by frames or by wall time, whichever is further).
float period_phase()
{
    float4 c = clock.Sample(pointSampler, float2(0.5, 0.5));
    if (restart_seconds <= 0.5) return 0.5;
    return saturate(max(c.g / (restart_seconds * 30.0), (time - c.b) / restart_seconds));
}

// Luma relative to the frame mean: the mean maps to 0.5, so one threshold works on dim and bright footage.
float rel_luma(float3 rgb)
{
    float m = meanl.Sample(pointSampler, float2(0.5, 0.5)).r;
    return saturate(0.5 + (dot(rgb, float3(0.299, 0.587, 0.114)) - m) * 1.5);
}

#define REACH 11.0

float luma_at(float2 uv)
{
    return dot(image.Sample(textureSampler, uv).rgb, float3(0.299, 0.587, 0.114));
}

float4 rd_at(float2 uv)
{
    // Iteration 0 continues from the last frame; later iterations from the previous iteration.
    float4 a = rd.Sample(pointSampler, uv);
    float4 b = rd_prev.Sample(pointSampler, uv);
    return (iteration == 0) ? b : a;
}

float4 PSStep(VertData v_in) : TARGET
{
    float2 uv = v_in.uv;
    float2 tx = pass_texel;
    float4 s = rd_at(uv);

    bool restart = clock.Sample(pointSampler, float2(0.5, 0.5)).r > 0.5;

    float lum = rel_luma(image.Sample(textureSampler, uv).rgb);

    if (s.a < 0.5 || reset || (restart && iteration == 0)) {
        // Start: food everywhere, a few drops of V on the brightest edges and on a sparse noise.
        return float4(1.0, 0.0, 0.0, 1.0);
    }

    float4 n  = rd_at(uv + float2(0.0, -tx.y));
    float4 so = rd_at(uv + float2(0.0,  tx.y));
    float4 e  = rd_at(uv + float2( tx.x, 0.0));
    float4 w  = rd_at(uv + float2(-tx.x, 0.0));
    float4 ne = rd_at(uv + float2( tx.x, -tx.y));
    float4 nw = rd_at(uv + float2(-tx.x, -tx.y));
    float4 se = rd_at(uv + float2( tx.x,  tx.y));
    float4 sw = rd_at(uv + float2(-tx.x,  tx.y));
    float reach_n = max(max(n.b, so.b), max(e.b, w.b));
    float2 lap = 0.2 * (n.rg + so.rg + e.rg + w.rg) + 0.05 * (ne.rg + nw.rg + se.rg + sw.rg) - s.rg;

    float F = 0.0545;
    float k = 0.062;
    if (preset == 1) { F = 0.030;  k = 0.0565; }
    else if (preset == 2) { F = 0.029; k = 0.057; }
    else if (preset == 3) { F = 0.0367; k = 0.0649; }
    F += (lum - 0.5) * 0.03 * follow;

    float uvv = s.r * s.g * s.g;
    float U = s.r + 1.0 * lap.r - uvv + F * (1.0 - s.r);
    float V = s.g + 0.5 * lap.g + uvv - (F + k) * s.g;

    // Camera edges plant seeds: a thick band of V on every strong edge.
    if (seed_edges > 0.0) {
        float edge = 0.0;
        for (int q = 1; q <= 3; q++) {
            float2 o = float2(float(q) * 2.0, float(q) * 2.0) * tx;
            float l1 = luma_at(uv + float2(o.x, 0.0)) - luma_at(uv - float2(o.x, 0.0));
            float l2 = luma_at(uv + float2(0.0, o.y)) - luma_at(uv - float2(0.0, o.y));
            edge = max(edge, sqrt(l1 * l1 + l2 * l2));
        }
        float seed = saturate(edge * 4.0 - 0.3) * seed_edges;
        // Plant drops on about a third of the edge texels (fixed per texel), not a solid band, so moving edges
        // leave coral sprouts instead of smearing flat stripes.
        float2 cell = floor(uv * pass_size);
        float drop = frac(sin(dot(cell, float2(12.9898, 78.233))) * 43758.5453);
        V = max(V, seed * step(drop, 0.35));
        reach_n = max(reach_n, saturate(seed * 8.0) + 1.0 / REACH);
    }
    // Leash: the pattern only lives within REACH texels of an edge seen recently, so it borders the picture's
    // edges instead of flooding the frame (and trails behind moving things die within a few frames).
    float reach = saturate(reach_n - 1.0 / REACH);
    V *= lerp(0.75, 1.0, smoothstep(0.0, 0.35, reach));
    // The pattern dies off on the brighter parts of the picture (skin, white shirts), so faces stay clear.
    V *= 1.0 - follow * 0.12 * smoothstep(0.45, 0.65, lum);
    U = clamp(U, 0.0, 1.0);
    V = clamp(V, 0.0, 1.0);
    return float4(U, V, reach, 1.0);
}

float4 PSDraw(VertData v_in) : TARGET
{
    float4 base = image.Sample(textureSampler, v_in.uv);
    float V = rd.Sample(textureSampler, v_in.uv).g;
    float p = smoothstep(0.08, 0.30, V);
    float lum = dot(base.rgb, float3(0.299, 0.587, 0.114));
    float3 skin = pattern_color.rgb * (0.55 + 0.6 * lum);
    // dark rim where the pattern is thin gives it relief
    float rim = smoothstep(0.02, 0.10, V) - p;
    skin = lerp(skin, skin * 0.35, rim);
    float3 shown = lerp(base.rgb, skin, saturate(p + rim * 0.6));
    // Fade in after a restart and out before the next one.
    float vis = 1.0;
    if (restart_seconds > 0.5) {
        float ph = period_phase();
        vis = saturate(min(ph, 1.0 - ph) * restart_seconds / 1.5);
    }
    float3 rgb = lerp(base.rgb, shown, mix_amount * vis);
    if (show_chemical)
        rgb = lerp(float3(0.0, 0.0, 0.0), pattern_color.rgb, saturate(V * 2.0));
    return float4(rgb, base.a);
}

technique Step { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSStep(v_in); } }
technique Draw { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSDraw(v_in); } }
technique Clock { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSClock(v_in); } }
technique Mean { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSMean(v_in); } }
