// Bass Bounce: zoom pulse + chromatic split driven by the audio level.
//   env: a 1x1 rgba32f state pass holding a smoothed loudness envelope (0..1)
//        fast attack (~0.03 s), slower release (~0.15 s)
//   out: zoom IN by 1 + zoom_amount * env (never out, so no edges are revealed),
//        red and blue shifted apart radially by split_amount * env
// audio_level is in dB (<= 0). With no source selected it is very low and the picture passes through.

uniform float audio_level;
uniform float sensitivity;
uniform float zoom_amount;
uniform float split_amount;

uniform texture2d env;
uniform texture2d env_prev;

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

float4 PSEnv(VertData v_in) : TARGET
{
    float prev = env_prev.Sample(textureSampler, v_in.uv).r;
    float floor_db = lerp(-12.0, -52.0, sensitivity);
    float t = saturate((audio_level - floor_db) / 12.0);
    t = t * t;
    float tau = (t > prev) ? 0.03 : 0.15;
    float k = 1.0 - exp(-min(delta_time, 0.2) / tau);
    float e = prev + (t - prev) * k;
    return float4(e, 0.0, 0.0, 1.0);
}

float4 PSDraw(VertData v_in) : TARGET
{
    float e = env.Sample(textureSampler, float2(0.5, 0.5)).r;
    float z = 1.0 + zoom_amount * e;
    float2 uv = 0.5 + (v_in.uv - 0.5) / z;
    float2 d = (uv - 0.5) * split_amount * e;
    float4 c = image.Sample(textureSampler, uv);
    float r = image.Sample(textureSampler, uv + d).r;
    float b = image.Sample(textureSampler, uv - d).b;
    return float4(r, c.g, b, c.a);
}

technique Env  { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSEnv(v_in); } }
technique Draw { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSDraw(v_in); } }
