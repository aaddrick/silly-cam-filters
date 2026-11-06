// Falling Sand: a Margolus-neighbourhood sand automaton on a 320x180 grid (rgba32f state pass).
// A cell is rgb = colour, a = 1 for sand, 0.5 for empty, 0 before the first frame.
// Each step works on 2x2 blocks; the block grid shifts by one cell on every other step.
// Moves swap cell contents, so sand is never created or lost by falling.

uniform float threshold;
uniform int gravity_steps;
uniform float spawn_rate;
uniform float initial_sand;
uniform float sink_rate;
uniform float evaporate;
uniform float restart_seconds;
uniform bool reset;
uniform float4 sand_tint;
uniform float tint_amount;
uniform bool sand_only;

uniform texture2d sand;
uniform texture2d sand_prev;

uniform float2 pass_size;
uniform int iteration;
uniform int iterations;

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
            float2 p = (float2(float(i), float(j)) + 0.5) / 8.0 + v_in.uv * 0.0;
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

float luma_at(float2 uv)
{
    return dot(image.Sample(textureSampler, uv).rgb, float3(0.299, 0.587, 0.114));
}

float4 sand_at(float2 uv)
{
    float4 a = sand.Sample(pointSampler, uv);
    float4 b = sand_prev.Sample(pointSampler, uv);
    return (iteration == 0) ? b : a;
}

float4 EMPTY() { return float4(0.0, 0.0, 0.0, 0.5); }

// Content of cell p. Outside the grid: sides and bottom are walls (a = -1), the top is empty.
float4 cell_at(float2 p)
{
    if (p.x < 0.0 || p.x >= pass_size.x || p.y >= pass_size.y)
        return float4(0.0, 0.0, 0.0, -1.0);
    if (p.y < 0.0)
        return EMPTY();
    return sand_at((p + 0.5) / pass_size);
}

bool is_sand(float4 c) { return c.a > 0.75; }
bool is_empty(float4 c) { return c.a > 0.25 && c.a < 0.75; }
bool is_occ(float4 c) { return c.a > 0.75 || c.a < 0.0; }

float4 PSSand(VertData v_in) : TARGET
{
    float2 t = floor(v_in.uv * pass_size);
    float4 self = sand_at((t + 0.5) / pass_size);

    bool restart = false;
    if (restart_seconds > 0.5)
        restart = frame_index > 0 && (frame_index % int(restart_seconds * 30.0)) == 0;

    if (self.a < 0.1 || reset || (restart && iteration == 0)) {
        // Seed: some of the bright pixels become sand.
        float2 uv = (t + 0.5) / pass_size;
        float4 col = image.Sample(textureSampler, uv);
        float l = rel_luma(col.rgb);
        bool s = l > threshold && hash21(t, 3.1 + rand_seed) < initial_sand;
        return s ? float4(col.rgb, 1.0) : EMPTY();
    }

    float par = fmod(float(frame_index * iterations + iteration), 2.0);
    float2 b = floor((t + par) / 2.0) * 2.0 - par;
    float2 l = t - b;

    float4 A = cell_at(b);
    float4 B = cell_at(b + float2(1.0, 0.0));
    float4 C = cell_at(b + float2(0.0, 1.0));
    float4 D = cell_at(b + float2(1.0, 1.0));

    bool fallL = is_sand(A) && is_empty(C);
    bool fallR = is_sand(B) && is_empty(D);
    bool slideAD = !fallL && !fallR && is_sand(A) && is_occ(C) && is_empty(D) && is_empty(B);
    bool slideBC = !fallL && !fallR && is_sand(B) && is_occ(D) && is_empty(C) && is_empty(A);

    float4 outc = self;
    if (l.x < 0.5 && l.y < 0.5) {            // A
        if (fallL) outc = C; else if (slideAD) outc = D;
    } else if (l.x > 0.5 && l.y < 0.5) {     // B
        if (fallR) outc = D; else if (slideBC) outc = C;
    } else if (l.x < 0.5 && l.y > 0.5) {     // C
        if (fallL) outc = A; else if (slideBC) outc = B;
    } else {                                 // D
        if (fallR) outc = B; else if (slideAD) outc = A;
    }

    // Sink at the bottom row.
    if (is_sand(outc) && t.y > pass_size.y - 1.5 && hash21(t, float(frame_index) * 0.37 + float(iteration)) < sink_rate)
        outc = EMPTY();

    // Sand evaporates slowly everywhere, so the pile reaches a steady height instead of burying the picture.
    if (is_sand(outc) && evaporate > 0.0 && hash21(t, float(frame_index) * 0.53 + float(iteration) * 7.0 + 31.0) < evaporate)
        outc = EMPTY();

    // New sand from bright camera pixels.
    if (is_empty(outc) && spawn_rate > 0.0 && iteration == 0) {
        float2 uv = (t + 0.5) / pass_size;
        float4 col = image.Sample(textureSampler, uv);
        float lm = rel_luma(col.rgb);
        if (lm > threshold && hash21(t, float(frame_index) * 0.61 + 9.0) < spawn_rate)
            outc = float4(col.rgb, 1.0);
    }
    return outc;
}

float4 PSDraw(VertData v_in) : TARGET
{
    float4 base = image.Sample(textureSampler, v_in.uv);
    float2 g = v_in.uv * pass_size;
    float4 s = sand.Sample(pointSampler, v_in.uv);
    float on = step(0.75, s.a);
    float2 f = frac(g);
    float grain = 0.88 + 0.12 * hash21(floor(g), 5.0);
    float edge = (min(f.x, f.y) > 0.08) ? 1.0 : 0.85;
    float3 col = lerp(s.rgb, sand_tint.rgb * max(dot(s.rgb, float3(0.299, 0.587, 0.114)), 0.35) * 1.4, tint_amount);
    col = saturate(col * grain * edge);
    float3 bg = sand_only ? float3(0.0, 0.0, 0.0) : base.rgb;
    return float4(lerp(bg, col, on), base.a);
}

technique Sand { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSSand(v_in); } }
technique Draw { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSDraw(v_in); } }
technique Mean { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSMean(v_in); } }
