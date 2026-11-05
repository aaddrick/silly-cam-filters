// Retro Effects: Dither (ported from FiniteSingularity's obs-retro-effects, GPL-2.0)
// Ordered (1): Bayer matrix (2x2, 4x4 or 8x8), computed from bits instead of a table.
// Unordered (2): Hilbert-curve R1 "blue noise" (https://www.shadertoy.com/view/cl2GRm),
//                done in float math instead of integer bit operations.

uniform int   dither_type;
uniform int   dither_bayer_size;
uniform float dither_size;
uniform int   dither_color_steps;
uniform bool  dither_mono;
uniform bool  dither_round;
uniform float dither_contrast;
uniform float dither_gamma;
uniform float dither_offset_x;
uniform float dither_offset_y;

uniform float2 uv_size;

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

// Floor modulo (always 0..y), safe for negative x.
float fmod_pos(float x, float y)
{
    return x - y * floor(x / y);
}

float RGBToLum(float3 color)
{
    return 0.299 * color.r + 0.587 * color.g + 0.114 * color.b;
}

// ---- UV / texel / dither-pixel conversions (as in dither-blue-noise.effect)

float dsize()
{
    return max(dither_size, 0.01);
}

float2 txFromUv(float2 uv)  { return floor(uv * uv_size); }
float2 uvFromTx(float2 tx)  { return (tx + 0.5) / uv_size; }
float2 pxFromTx(float2 tx)  { return floor(tx / dsize()); }
float2 txFromPx(float2 px)  { return floor((px + 0.5) * dsize()); }
float2 uvFromPx(float2 px)  { return uvFromTx(txFromPx(px)); }
float2 pxFromUv(float2 uv)  { return pxFromTx(txFromUv(uv)); }

// ---- Hilbert R1 noise

#define HILBERT_WIDTH 128.0

float HilbertIndex(float2 p)
{
    // The original works on int bits; only the low 7 bits matter, so wrap first.
    // int() truncates toward zero, so truncate before wrapping.
    float2 t = sign(p) * floor(abs(p));
    float2 pos = float2(fmod_pos(t.x, HILBERT_WIDTH), fmod_pos(t.y, HILBERT_WIDTH));
    float index = 0.0;
    float level = HILBERT_WIDTH / 2.0;
    for (int i = 0; i < 7; i++) {
        float rx = fmod_pos(floor(pos.x / level), 2.0);
        float ry = fmod_pos(floor(pos.y / level), 2.0);
        // (3 * rx) ^ ry for rx, ry in {0, 1}
        index += level * level * (3.0 * rx + ry - 2.0 * rx * ry);
        if (ry < 0.5) {
            if (rx > 0.5) {
                pos = float2(HILBERT_WIDTH - 1.0, HILBERT_WIDTH - 1.0) - pos;
            }
            pos = pos.yx;
        }
        level = level / 2.0;
    }
    return index;
}

float HilbertR1Noise(float2 p)
{
    return frac(0.5 + 0.61803398874989484820 * HilbertIndex(p));
}

float3 TriWave(float3 z)
{
    return lerp(2.0 * z, 2.0 - 2.0 * z, step(0.5, z));
}

float3 BlueNoise(float2 p)
{
    float3 noise = float3(
        HilbertR1Noise(p),
        HilbertR1Noise(p + float2(1234.0, 0.0)),
        HilbertR1Noise(p + float2(0.0, 1234.0)));
    return TriWave(noise);
}

// ---- Bayer matrix, built from the bits of the pixel position.
// M(2n)(x, y) = 4 * M2(x mod 2, y mod 2) + M(n)(x / 2, y / 2), M2 = [0 2; 3 1].

float get_bayer(float2 px)
{
    float n = 4.0;
    float levels = 2.0;
    if (dither_bayer_size == 2) {
        n = 2.0;
        levels = 1.0;
    } else if (dither_bayer_size == 8) {
        n = 8.0;
        levels = 3.0;
    }
    float2 c = float2(fmod_pos(px.x, n), fmod_pos(px.y, n));
    float value = 0.0;
    float weight = n * n / 4.0;
    for (int i = 0; i < 3; i++) {
        if (float(i) >= levels) break;
        float xb = fmod_pos(c.x, 2.0);
        float yb = fmod_pos(c.y, 2.0);
        value += weight * (2.0 * abs(xb - yb) + yb);
        c = floor(c / 2.0);
        weight = weight / 4.0;
    }
    return value / (n * n);
}

// ---- Color

float4 sampleSource(float2 uv)
{
    float4 color;
    if (dither_round) {
        color = image.Sample(textureSampler, uvFromPx(pxFromUv(uv)));
    } else {
        color = image.Sample(textureSampler, uv);
    }

    float contrast = dither_contrast * 255.0;
    float gammaCorrection = 1.0 / dither_gamma;
    float contrastFactor = (259.0 * (contrast + 255.0)) / (255.0 * (259.0 - contrast));

    color.rgb = pow(max(color.rgb, float3(0.0, 0.0, 0.0)), float3(gammaCorrection, gammaCorrection, gammaCorrection));
    color.rgb = saturate(contrastFactor * (color.rgb - 0.5) + 0.5);

    if (dither_mono) {
        float lum = RGBToLum(color.rgb);
        color.rgb = float3(lum, lum, lum);
    }
    return color;
}

float4 PSDither(VertData v_in) : TARGET
{
    float4 color = sampleSource(v_in.uv);
    float2 px = pxFromUv(v_in.uv);

    float noise;
    if (dither_type == 2) {
        noise = RGBToLum(BlueNoise(px - float2(dither_offset_x, dither_offset_y)));
    } else {
        noise = get_bayer(px);
    }

    float steps = float(dither_color_steps);
    color.rgb = floor(color.rgb * steps + noise) / steps;
    return color;
}

technique Draw { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSDither(v_in); } }
