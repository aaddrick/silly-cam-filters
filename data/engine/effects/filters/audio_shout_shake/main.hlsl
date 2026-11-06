// Shout Shake: above a loudness threshold the picture shakes, the face swells and a red vignette fades in.
//   env: 1x1 rgba32f  r = drive (0..1, smoothed: attack ~0.06 s, release ~0.25 s) for shake and swell,
//                     g = vignette level, moves at most 1/0.3 per second (>= 0.3 s attack and decay, no flash),
//                     b = face presence (S1 sf_presence_step, 0.25 s)
//   drive = (level - threshold) / 15 dB: speech just over the threshold gives a little, a shout gives full.
// Shake zooms in just enough (1/(1-2*amp)) that the offset never reveals the edge.
// Swell: sf_bulge at the face-oval centre, 1.1-1.3x at defaults, only while the face is tracked.
// No audio source = level very low = drive 0 = exact passthrough.
@include "silly_face.hlsl"

uniform float audio_level;
uniform float threshold;
uniform float shake_amount;
uniform float swell;
uniform float vignette;
uniform float elapsed_time;

uniform texture2d env;
uniform texture2d env_prev;

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

float4 PSEnv(VertData v_in) : TARGET
{
    float4 p = env_prev.Sample(sf_point_sampler, v_in.uv);
    float dt = min(delta_time, 0.2);
    float target = saturate((audio_level - threshold) / 15.0);
    float tau = (target > p.r) ? 0.06 : 0.25;
    float d = p.r + (target - p.r) * (1.0 - exp(-dt / tau));
    float vt = smoothstep(0.0, 0.5, d);
    float step_max = dt / 0.3;
    float v = p.g + clamp(vt - p.g, -step_max, step_max);
    float pres = sf_presence_step(p.b, 0.25);
    return float4(d, v, pres, 1.0);
}

float4 PSDraw(VertData v_in) : TARGET
{
    float4 e = env.Sample(sf_point_sampler, float2(0.5, 0.5));
    float d = e.r;
    float v = e.g;
    float pres = e.b;
    float2 uv = v_in.uv;
    if (d < 0.002 && v < 0.002) { return image.Sample(textureSampler, uv); }

    // shake: zoom in by enough to cover the offset, then jitter
    float amp = shake_amount * d;
    float z = 1.0 / (1.0 - 2.0 * amp);
    float t = elapsed_time;
    float2 off = amp * float2(sin(t * 63.0) + 0.5 * sin(t * 97.0 + 1.3),
                              cos(t * 71.0) + 0.5 * sin(t * 113.0 + 0.4)) / 1.5;
    float2 suv = 0.5 + (uv - 0.5) / z + off;

    // face swell (bulge around the face oval centre), only with a tracked face
    if (sf_face_ok() && pres > 0.0) {
        float2 hs = sf_face_half_size_iso();
        float rad = 1.7 * max(hs.x, hs.y);
        float2 w = sf_bulge(suv, sf_face_center(), rad, swell * d * pres);
        suv = w;
    }
    float4 c = image.Sample(textureSampler, suv);

    // red vignette (screen space, not shaken)
    float2 q = (uv - 0.5) * float2(1.0, 0.8);
    float vr = smoothstep(0.25, 0.75, length(q));
    float m = vignette * v * vr;
    float3 red = float3(0.85, 0.05, 0.05);
    float3 rgb = lerp(c.rgb, red, 0.75 * m);
    return float4(rgb, c.a);
}

technique Env  { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSEnv(v_in); } }
technique Draw { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSDraw(v_in); } }
