// Retro: Bloom. Port of the Bloom filter from obs-retro-effects 1.0.2 by FiniteSingularity
// (GPL-2.0, https://github.com/FiniteSingularity/obs-retro-effects).
//   bright: brightness threshold (brightness-threshold.effect), half size
//   blurh:  horizontal gaussian blur, sigma = Size px (blur.c, gaussian_area_blur)
//   blurv:  vertical gaussian blur
//   result: source + intensity * bloom (bloom-combine.effect)

uniform float bloom_intensity;      // %
uniform float bloom_size;           // px
uniform float bloom_threshold;      // %
uniform int bloom_threshold_type;   // 0 luminance, 1 red, 2 green, 3 blue, 4 custom
uniform float bloom_red_level;
uniform float bloom_green_level;
uniform float bloom_blue_level;

uniform float2 pass_texel;

uniform texture2d bright;
uniform texture2d blurh;
uniform texture2d blurv;

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

float3 levels()
{
    if (bloom_threshold_type == 1) return float3(1.0, -0.5, -0.5);
    if (bloom_threshold_type == 2) return float3(-0.5, 1.0, -0.5);
    if (bloom_threshold_type == 3) return float3(-0.5, -0.5, 1.0);
    if (bloom_threshold_type == 4) return float3(bloom_red_level, bloom_green_level, bloom_blue_level);
    return float3(0.299, 0.587, 0.114);
}

float3 threshold_rgb(float3 c, float3 lv)
{
    return dot(c, lv) > bloom_threshold / 100.0 ? c : float3(0.0, 0.0, 0.0);
}

// Half-size bright pass: threshold each of the 4 source pixels, then average them.
float4 PSBright(VertData v_in) : TARGET
{
    float3 lv = levels();
    float2 h = float2(upixel, vpixel) * 0.5;
    float3 acc = threshold_rgb(image.Sample(textureSampler, v_in.uv + float2(-h.x, -h.y)).rgb, lv);
    acc += threshold_rgb(image.Sample(textureSampler, v_in.uv + float2( h.x, -h.y)).rgb, lv);
    acc += threshold_rgb(image.Sample(textureSampler, v_in.uv + float2(-h.x,  h.y)).rgb, lv);
    acc += threshold_rgb(image.Sample(textureSampler, v_in.uv + float2( h.x,  h.y)).rgb, lv);
    return float4(acc * 0.25, 1.0);
}

// Gaussian with sigma = bloom_size source px (the C kernel spans 3 sigma, capped at 250 px).
// Passes are half size, so sigma is halved. At most 48 taps per side; the tap spacing
// grows for big sizes.
float4 PSBlurH(VertData v_in) : TARGET
{
    float sigma = min(bloom_size, 250.0 / 3.0) * 0.5;
    float3 acc = bright.Sample(textureSampler, v_in.uv).rgb;
    if (sigma < 0.01) {
        return float4(acc, 1.0);
    }
    float span = 3.0 * sigma;
    float stp = max(1.0, span / 48.0);
    int n = int(ceil(span / stp));
    float wsum = 1.0;
    for (int i = 1; i <= 48; i++) {
        if (i > n) break;
        float x = float(i) * stp;
        float w = exp(-x * x / (2.0 * sigma * sigma));
        float2 o = float2(x * pass_texel.x, 0.0);
        acc += (bright.Sample(textureSampler, v_in.uv + o).rgb + bright.Sample(textureSampler, v_in.uv - o).rgb) * w;
        wsum += 2.0 * w;
    }
    return float4(acc / wsum, 1.0);
}

float4 PSBlurV(VertData v_in) : TARGET
{
    float sigma = min(bloom_size, 250.0 / 3.0) * 0.5;
    float3 acc = blurh.Sample(textureSampler, v_in.uv).rgb;
    if (sigma < 0.01) {
        return float4(acc, 1.0);
    }
    float span = 3.0 * sigma;
    float stp = max(1.0, span / 48.0);
    int n = int(ceil(span / stp));
    float wsum = 1.0;
    for (int i = 1; i <= 48; i++) {
        if (i > n) break;
        float x = float(i) * stp;
        float w = exp(-x * x / (2.0 * sigma * sigma));
        float2 o = float2(0.0, x * pass_texel.y);
        acc += (blurh.Sample(textureSampler, v_in.uv + o).rgb + blurh.Sample(textureSampler, v_in.uv - o).rgb) * w;
        wsum += 2.0 * w;
    }
    return float4(acc / wsum, 1.0);
}

float4 PSCombine(VertData v_in) : TARGET
{
    float4 color = image.Sample(textureSampler, v_in.uv);
    // Below 0.01 px the C code skips the blur and adds the thresholded image.
    float3 bloom = bloom_size < 0.01 ? threshold_rgb(color.rgb, levels()) : blurv.Sample(textureSampler, v_in.uv).rgb;
    return float4(color.rgb + bloom_intensity / 100.0 * bloom, color.a);
}

technique Bright  { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSBright(v_in); } }
technique BlurH   { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSBlurH(v_in); } }
technique BlurV   { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSBlurV(v_in); } }
technique Combine { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSCombine(v_in); } }
