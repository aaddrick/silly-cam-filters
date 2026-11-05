// Glow: a three-pass bloom. A worked example of engine passes (docs/ENGINE.md).
//   bright: keep the bright parts of the source, at half size
//   blur:   blur them; each iteration reads the previous one through `blur`
//   result: add the blurred light back onto the source

uniform float threshold;
uniform float strength;
uniform float radius;
uniform int blur_passes;
uniform float4 tint;

// Pass outputs, bound by the engine
uniform texture2d bright;
uniform texture2d blur;

uniform float2 pass_texel;
uniform int iteration;

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

float4 PSBright(VertData v_in) : TARGET
{
    float4 c = image.Sample(textureSampler, v_in.uv);
    float lum = dot(c.rgb, float3(0.299, 0.587, 0.114));
    float k = smoothstep(threshold, threshold + 0.1, lum);
    return float4(c.rgb * k, 1.0);
}

float gauss_weight(int i)
{
    if (i == 0) return 0.227027;
    if (i == 1) return 0.1945946;
    if (i == 2) return 0.1216216;
    if (i == 3) return 0.054054;
    return 0.016216;
}

float4 PSBlur(VertData v_in) : TARGET
{
    // The first iteration reads `bright`; later ones read their own previous output.
    // Iterations alternate horizontal and vertical.
    float2 dir = (iteration % 2 == 0) ? float2(pass_texel.x, 0.0) : float2(0.0, pass_texel.y);
    dir *= radius;
    float3 acc = float3(0.0, 0.0, 0.0);
    if (iteration == 0) {
        acc = bright.Sample(textureSampler, v_in.uv).rgb * gauss_weight(0);
        for (int i = 1; i < 5; i++) {
            acc += bright.Sample(textureSampler, v_in.uv + dir * float(i)).rgb * gauss_weight(i);
            acc += bright.Sample(textureSampler, v_in.uv - dir * float(i)).rgb * gauss_weight(i);
        }
    } else {
        acc = blur.Sample(textureSampler, v_in.uv).rgb * gauss_weight(0);
        for (int i = 1; i < 5; i++) {
            acc += blur.Sample(textureSampler, v_in.uv + dir * float(i)).rgb * gauss_weight(i);
            acc += blur.Sample(textureSampler, v_in.uv - dir * float(i)).rgb * gauss_weight(i);
        }
    }
    return float4(acc, 1.0);
}

float4 PSCombine(VertData v_in) : TARGET
{
    float4 base = image.Sample(textureSampler, v_in.uv);
    float3 glow = blur.Sample(textureSampler, v_in.uv).rgb * tint.rgb * strength;
    return float4(base.rgb + glow, base.a);
}

technique Bright  { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSBright(v_in); } }
technique Blur    { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSBlur(v_in); } }
technique Combine { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSCombine(v_in); } }
