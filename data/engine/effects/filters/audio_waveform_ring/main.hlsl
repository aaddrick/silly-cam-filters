// Voice Waveform Ring: a ring around the face whose spikes show the last ~2 s of the audio level.
//   env : 1x1 rgba32f  r = smoothed level (fast attack, slower release), g = tick timer,
//                      b = slow "activity" (max-hold, decays ~1.5 s), a = 1 on frames that push history
//   pres: 1x1 rgba32f  r = face presence (S1 sf_presence_step, fades the ring in/out in 0.25 s)
//   hist: 64x1 rgba16f history of r, shifted at 30 Hz (newest at texel 0); drawn mirrored around the
//         ring from the top (newest) to the bottom (oldest)
// Ring centre and size come from the S1 face oval (landmarks 10/152/234/454), not fd_bbox.
// audio_level is in dB (<= 0). No source = very low = activity 0 = exact passthrough.
@include "silly_face.hlsl"

uniform float audio_level;
uniform float sensitivity;
uniform float4 ring_color;
uniform float thickness;
uniform float spike_height;

uniform texture2d env;
uniform texture2d env_prev;
uniform texture2d pres;
uniform texture2d pres_prev;
uniform texture2d hist;
uniform texture2d hist_prev;

sampler_state textureSampler {
    Filter   = Linear;
    AddressU = Clamp;
    AddressV = Clamp;
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

#define TICK 0.0333333

float4 PSEnv(VertData v_in) : TARGET
{
    float4 p = env_prev.Sample(sf_point_sampler, v_in.uv);
    float dt = min(delta_time, 0.2);
    float floor_db = lerp(-20.0, -60.0, sensitivity);
    float t = saturate((audio_level - floor_db) / 25.0);
    float tau = (t > p.r) ? 0.03 : 0.12;
    float e = p.r + (t - p.r) * (1.0 - exp(-dt / tau));
    float acc = p.g + dt;
    float tick = 0.0;
    if (acc >= TICK) { acc = min(acc - TICK, TICK); tick = 1.0; }
    float act = max(e, p.b * exp(-dt / 1.5));
    return float4(e, acc, act, tick);
}

float4 PSPres(VertData v_in) : TARGET
{
    float p = pres_prev.Sample(sf_point_sampler, v_in.uv).r;
    return float4(sf_presence_step(p, 0.25), 0.0, 0.0, 1.0);
}

float4 PSHist(VertData v_in) : TARGET
{
    float4 e = env.Sample(sf_point_sampler, float2(0.5, 0.5));
    float i = floor(v_in.uv.x * 64.0);
    float cur = hist_prev.Sample(sf_point_sampler, v_in.uv).r;
    if (e.a > 0.5) {
        float shifted = hist_prev.Sample(sf_point_sampler, float2((i - 0.5) / 64.0, 0.5)).r;
        cur = (i < 0.5) ? e.r : shifted;
    }
    return float4(cur, 0.0, 0.0, 1.0);
}

float4 PSDraw(VertData v_in) : TARGET
{
    float4 src = image.Sample(textureSampler, v_in.uv);
    float presence = pres.Sample(sf_point_sampler, float2(0.5, 0.5)).r;
    float act = env.Sample(sf_point_sampler, float2(0.5, 0.5)).b;
    float alpha = presence * smoothstep(0.02, 0.15, act);
    if (alpha <= 0.0 || !sf_face_ok()) { return src; }

    float4 o = sf_face_oval_local();
    float2 q = (sf_to_local(v_in.uv) - o.xy) / o.zw;
    float r = length(q);
    float hmean = 0.5 * (o.z + o.w);
    float R0 = 1.3;
    float dist = (r - R0) * hmean;               // distance from the ring line, face-scale units

    // angle from the top, mirrored left/right: 0 at top (newest), 1 at the bottom (oldest)
    float u = abs(atan2(q.x, -q.y)) / 3.14159265;
    float N = 40.0;                               // bars per side
    float bar = floor(u * N);
    float ub = (bar + 0.5) / N;
    float w = hist.Sample(textureSampler, float2(ub * 0.984 + 0.008, 0.5)).r;
    float h = pow(w, 0.8) * spike_height;
    float gap = abs(frac(u * N) - 0.5) * 2.0;     // 0 bar centre .. 1 bar edge
    float bar_mask = 1.0 - smoothstep(0.55, 0.8, gap);

    float aa = 0.02;
    float base = 1.0 - smoothstep(0.5 * thickness, 0.5 * thickness + aa, abs(dist));
    float spike = smoothstep(-aa, 0.0, dist) * (1.0 - smoothstep(h - aa, h, dist)) * bar_mask * step(0.001, h);
    float m = saturate(max(base * 0.7, spike));
    float3 col = lerp(ring_color.rgb, float3(1.0, 1.0, 1.0), 0.35 * spike);
    float3 glow = ring_color.rgb * 0.25 * exp(-abs(dist) / 0.15) * saturate(w * 1.5);
    float3 rgb = src.rgb + glow * alpha;
    rgb = lerp(rgb, col, m * alpha);
    return float4(rgb, src.a);
}

technique Env  { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSEnv(v_in); } }
technique Pres { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSPres(v_in); } }
technique Hist { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSHist(v_in); } }
technique Draw { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSDraw(v_in); } }
