// Retro: CRT. Port of the CRT filter from obs-retro-effects 1.0.2 by FiniteSingularity
// (GPL-2.0, https://github.com/FiniteSingularity/obs-retro-effects).
//   mask:   phosphor mask, vignette and rounded corners (crt.effect)
//   bright: brightness threshold of the mask output (brightness-threshold.effect), half size
//   blurh:  horizontal gaussian blur, sigma = Bloom Size px (blur.c, gaussian_area_blur)
//   blurv:  vertical gaussian blur
//   result: bloom combine (bloom-combine.effect) + barrel distortion and levels (crt-composite.effect)

uniform int crt_phosphor_type;
uniform float crt_mask_intensity;   // %
uniform float crt_bloom;            // px
uniform float crt_bloom_threshold;  // %
uniform float crt_bloom_intensity;  // %
uniform float crt_corner_radius;    // px
uniform float crt_barrel_distort;   // %
uniform float crt_vignette;         // %
uniform float crt_black_level;      // 0..255
uniform float crt_white_level;      // 0..255

uniform float2 uv_size;
uniform float2 pass_texel;

uniform texture2d mask;
uniform texture2d bright;
uniform texture2d blurh;
uniform texture2d blurv;

#define EPS 1.e-3

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

// Phosphor mask layouts 1-24, from crt.effect (weights by hunterk, public domain:
// libretro slang-shaders include/subpixel_masks.h). Generated as if-chains because
// OBS's HLSL->GLSL translation does not accept array initializers.
// Returns a color code: bit 4 = red, bit 2 = green, bit 1 = blue. -1 = no mask.
int mask_code(int phos_layout, int x, int y)
{
	if (phos_layout == 1) {
		int z = x % 2;
		if (z == 0) return 5; return 2;
	}
	if (phos_layout == 2) {
		int w = y % 2;
		int z = x % 2;
		if (w == 0) { if (z == 0) return 5; return 2; }
		if (w == 1) { if (z == 0) return 2; return 5; }
		return 0;
	}
	if (phos_layout == 3) {
		int w = y % 3;
		int z = x % 4;
		if (w == 0) { if (z == 0) return 5; if (z == 1) return 2; if (z == 2) return 0; return 0; }
		if (w == 1) { if (z == 0) return 5; if (z == 1) return 2; if (z == 2) return 5; return 2; }
		if (w == 2) { if (z == 0) return 0; if (z == 1) return 0; if (z == 2) return 5; return 2; }
		return 0;
	}
	if (phos_layout == 4) {
		int z = x % 2;
		if (z == 0) return 6; return 1;
	}
	if (phos_layout == 5) {
		int w = y % 2;
		int z = x % 2;
		if (w == 0) { if (z == 0) return 6; return 1; }
		if (w == 1) { if (z == 0) return 1; return 6; }
		return 0;
	}
	if (phos_layout == 6) {
		int z = x % 4;
		if (z == 0) return 4; if (z == 1) return 2; if (z == 2) return 1; return 0;
	}
	if (phos_layout == 7) {
		int z = x % 5;
		if (z == 0) return 4; if (z == 1) return 5; if (z == 2) return 1; if (z == 3) return 2; return 2;
	}
	if (phos_layout == 8) {
		int z = x % 7;
		if (z == 0) return 4; if (z == 1) return 4; if (z == 2) return 6; if (z == 3) return 2; if (z == 4) return 3; if (z == 5) return 1; return 1;
	}
	if (phos_layout == 9) {
		int z = x % 4;
		if (z == 0) return 4; if (z == 1) return 6; if (z == 2) return 3; return 1;
	}
	if (phos_layout == 10) {
		int z = x % 4;
		if (z == 0) return 4; if (z == 1) return 5; if (z == 2) return 3; return 2;
	}
	if (phos_layout == 11) {
		int w = y % 2;
		int z = x % 4;
		if (w == 0) { if (z == 0) return 4; if (z == 1) return 2; if (z == 2) return 1; return 0; }
		if (w == 1) { if (z == 0) return 1; if (z == 1) return 0; if (z == 2) return 4; return 2; }
		return 0;
	}
	if (phos_layout == 12) {
		int w = y % 2;
		int z = x % 4;
		if (w == 0) { if (z == 0) return 4; if (z == 1) return 6; if (z == 2) return 3; return 1; }
		if (w == 1) { if (z == 0) return 3; if (z == 1) return 1; if (z == 2) return 4; return 6; }
		return 0;
	}
	if (phos_layout == 13) {
		int w = y % 4;
		int z = x % 4;
		if (w == 0) { if (z == 0) return 4; if (z == 1) return 6; if (z == 2) return 3; return 1; }
		if (w == 1) { if (z == 0) return 4; if (z == 1) return 6; if (z == 2) return 3; return 1; }
		if (w == 2) { if (z == 0) return 3; if (z == 1) return 1; if (z == 2) return 4; return 6; }
		if (w == 3) { if (z == 0) return 3; if (z == 1) return 1; if (z == 2) return 4; return 6; }
		return 0;
	}
	if (phos_layout == 14) {
		int w = y % 3;
		int z = x % 6;
		if (w == 0) { if (z == 0) return 5; if (z == 1) return 2; if (z == 2) return 0; if (z == 3) return 0; if (z == 4) return 0; return 0; }
		if (w == 1) { if (z == 0) return 5; if (z == 1) return 2; if (z == 2) return 0; if (z == 3) return 5; if (z == 4) return 2; return 0; }
		if (w == 2) { if (z == 0) return 0; if (z == 1) return 0; if (z == 2) return 0; if (z == 3) return 5; if (z == 4) return 2; return 0; }
		return 0;
	}
	if (phos_layout == 15) {
		int w = y % 4;
		int z = x % 8;
		if (w == 0) { if (z == 0) return 4; if (z == 1) return 6; if (z == 2) return 3; if (z == 3) return 1; if (z == 4) return 4; if (z == 5) return 6; if (z == 6) return 3; return 1; }
		if (w == 1) { if (z == 0) return 4; if (z == 1) return 6; if (z == 2) return 3; if (z == 3) return 1; if (z == 4) return 0; if (z == 5) return 0; if (z == 6) return 0; return 0; }
		if (w == 2) { if (z == 0) return 4; if (z == 1) return 6; if (z == 2) return 3; if (z == 3) return 1; if (z == 4) return 4; if (z == 5) return 6; if (z == 6) return 3; return 1; }
		if (w == 3) { if (z == 0) return 0; if (z == 1) return 0; if (z == 2) return 0; if (z == 3) return 0; if (z == 4) return 4; if (z == 5) return 6; if (z == 6) return 3; return 1; }
		return 0;
	}
	if (phos_layout == 16) {
		int w = y % 3;
		int z = x % 4;
		if (w == 0) { if (z == 0) return 6; if (z == 1) return 1; if (z == 2) return 0; return 0; }
		if (w == 1) { if (z == 0) return 6; if (z == 1) return 1; if (z == 2) return 6; return 1; }
		if (w == 2) { if (z == 0) return 0; if (z == 1) return 0; if (z == 2) return 6; return 1; }
		return 0;
	}
	if (phos_layout == 17) {
		int w = y % 4;
		int z = x % 10;
		if (w == 0) { if (z == 0) return 4; if (z == 1) return 5; if (z == 2) return 1; if (z == 3) return 2; if (z == 4) return 2; if (z == 5) return 4; if (z == 6) return 5; if (z == 7) return 1; if (z == 8) return 2; return 2; }
		if (w == 1) { if (z == 0) return 0; if (z == 1) return 1; if (z == 2) return 1; if (z == 3) return 2; if (z == 4) return 2; if (z == 5) return 4; if (z == 6) return 4; if (z == 7) return 0; if (z == 8) return 0; return 0; }
		if (w == 2) { if (z == 0) return 4; if (z == 1) return 5; if (z == 2) return 1; if (z == 3) return 2; if (z == 4) return 2; if (z == 5) return 4; if (z == 6) return 5; if (z == 7) return 1; if (z == 8) return 2; return 2; }
		if (w == 3) { if (z == 0) return 4; if (z == 1) return 4; if (z == 2) return 0; if (z == 3) return 0; if (z == 4) return 0; if (z == 5) return 0; if (z == 6) return 1; if (z == 7) return 1; if (z == 8) return 2; return 2; }
		return 0;
	}
	if (phos_layout == 18) {
		int w = y % 4;
		int z = x % 10;
		if (w == 0) { if (z == 0) return 4; if (z == 1) return 6; if (z == 2) return 2; if (z == 3) return 1; if (z == 4) return 1; if (z == 5) return 4; if (z == 6) return 6; if (z == 7) return 2; if (z == 8) return 1; return 1; }
		if (w == 1) { if (z == 0) return 0; if (z == 1) return 2; if (z == 2) return 2; if (z == 3) return 1; if (z == 4) return 1; if (z == 5) return 4; if (z == 6) return 4; if (z == 7) return 0; if (z == 8) return 0; return 0; }
		if (w == 2) { if (z == 0) return 4; if (z == 1) return 6; if (z == 2) return 2; if (z == 3) return 1; if (z == 4) return 1; if (z == 5) return 4; if (z == 6) return 6; if (z == 7) return 2; if (z == 8) return 1; return 1; }
		if (w == 3) { if (z == 0) return 4; if (z == 1) return 4; if (z == 2) return 0; if (z == 3) return 0; if (z == 4) return 0; if (z == 5) return 0; if (z == 6) return 2; if (z == 7) return 2; if (z == 8) return 1; return 1; }
		return 0;
	}
	if (phos_layout == 19) {
		int w = y % 6;
		int z = x % 14;
		if (w == 0) { if (z == 0) return 4; if (z == 1) return 4; if (z == 2) return 6; if (z == 3) return 2; if (z == 4) return 3; if (z == 5) return 1; if (z == 6) return 1; if (z == 7) return 4; if (z == 8) return 4; if (z == 9) return 6; if (z == 10) return 2; if (z == 11) return 3; if (z == 12) return 1; return 1; }
		if (w == 1) { if (z == 0) return 4; if (z == 1) return 4; if (z == 2) return 6; if (z == 3) return 2; if (z == 4) return 3; if (z == 5) return 1; if (z == 6) return 1; if (z == 7) return 4; if (z == 8) return 4; if (z == 9) return 6; if (z == 10) return 2; if (z == 11) return 3; if (z == 12) return 1; return 1; }
		if (w == 2) { if (z == 0) return 4; if (z == 1) return 4; if (z == 2) return 6; if (z == 3) return 2; if (z == 4) return 3; if (z == 5) return 1; if (z == 6) return 1; if (z == 7) return 0; if (z == 8) return 0; if (z == 9) return 0; if (z == 10) return 0; if (z == 11) return 0; if (z == 12) return 0; return 0; }
		if (w == 3) { if (z == 0) return 4; if (z == 1) return 4; if (z == 2) return 6; if (z == 3) return 2; if (z == 4) return 3; if (z == 5) return 1; if (z == 6) return 1; if (z == 7) return 4; if (z == 8) return 4; if (z == 9) return 6; if (z == 10) return 2; if (z == 11) return 3; if (z == 12) return 1; return 1; }
		if (w == 4) { if (z == 0) return 4; if (z == 1) return 4; if (z == 2) return 6; if (z == 3) return 2; if (z == 4) return 3; if (z == 5) return 1; if (z == 6) return 1; if (z == 7) return 4; if (z == 8) return 4; if (z == 9) return 6; if (z == 10) return 2; if (z == 11) return 3; if (z == 12) return 1; return 1; }
		if (w == 5) { if (z == 0) return 0; if (z == 1) return 0; if (z == 2) return 0; if (z == 3) return 0; if (z == 4) return 0; if (z == 5) return 0; if (z == 6) return 0; if (z == 7) return 0; if (z == 8) return 4; if (z == 9) return 4; if (z == 10) return 6; if (z == 11) return 2; if (z == 12) return 3; return 1; }
		return 0;
	}
	if (phos_layout == 20) {
		int w = y % 4;
		int z = x % 4;
		if (w == 0) { if (z == 0) return 2; if (z == 1) return 5; if (z == 2) return 2; return 5; }
		if (w == 1) { if (z == 0) return 0; if (z == 1) return 1; if (z == 2) return 2; return 4; }
		if (w == 2) { if (z == 0) return 2; if (z == 1) return 5; if (z == 2) return 2; return 5; }
		if (w == 3) { if (z == 0) return 2; if (z == 1) return 4; if (z == 2) return 0; return 1; }
		return 0;
	}
	if (phos_layout == 21) {
		int w = y % 4;
		int z = x % 8;
		if (w == 0) { if (z == 0) return 4; if (z == 1) return 2; if (z == 2) return 1; if (z == 3) return 0; if (z == 4) return 4; if (z == 5) return 2; if (z == 6) return 1; return 0; }
		if (w == 1) { if (z == 0) return 4; if (z == 1) return 2; if (z == 2) return 1; if (z == 3) return 0; if (z == 4) return 0; if (z == 5) return 0; if (z == 6) return 0; return 0; }
		if (w == 2) { if (z == 0) return 4; if (z == 1) return 2; if (z == 2) return 1; if (z == 3) return 0; if (z == 4) return 4; if (z == 5) return 2; if (z == 6) return 1; return 0; }
		if (w == 3) { if (z == 0) return 0; if (z == 1) return 0; if (z == 2) return 0; if (z == 3) return 0; if (z == 4) return 4; if (z == 5) return 2; if (z == 6) return 1; return 0; }
		return 0;
	}
	if (phos_layout == 22) {
		int z = x % 3;
		if (z == 0) return 0; if (z == 1) return 7; return 7;
	}
	if (phos_layout == 23) {
		int z = x % 4;
		if (z == 0) return 0; if (z == 1) return 0; if (z == 2) return 7; return 7;
	}
	if (phos_layout == 24) {
		int w = y % 6;
		int z = x % 10;
		if (w == 0) { if (z == 0) return 2; if (z == 1) return 3; if (z == 2) return 1; if (z == 3) return 1; if (z == 4) return 1; if (z == 5) return 4; if (z == 6) return 4; if (z == 7) return 4; if (z == 8) return 6; return 2; }
		if (w == 1) { if (z == 0) return 2; if (z == 1) return 3; if (z == 2) return 1; if (z == 3) return 1; if (z == 4) return 1; if (z == 5) return 4; if (z == 6) return 4; if (z == 7) return 4; if (z == 8) return 6; return 2; }
		if (w == 2) { if (z == 0) return 2; if (z == 1) return 3; if (z == 2) return 1; if (z == 3) return 1; if (z == 4) return 1; if (z == 5) return 4; if (z == 6) return 4; if (z == 7) return 4; if (z == 8) return 6; return 2; }
		if (w == 3) { if (z == 0) return 4; if (z == 1) return 4; if (z == 2) return 4; if (z == 3) return 6; if (z == 4) return 2; if (z == 5) return 2; if (z == 6) return 3; if (z == 7) return 1; if (z == 8) return 1; return 1; }
		if (w == 4) { if (z == 0) return 4; if (z == 1) return 4; if (z == 2) return 4; if (z == 3) return 6; if (z == 4) return 2; if (z == 5) return 2; if (z == 6) return 3; if (z == 7) return 1; if (z == 8) return 1; return 1; }
		if (w == 5) { if (z == 0) return 4; if (z == 1) return 4; if (z == 2) return 4; if (z == 3) return 6; if (z == 4) return 2; if (z == 5) return 2; if (z == 6) return 3; if (z == 7) return 1; if (z == 8) return 1; return 1; }
		return 0;
	}
	return -1;
}

float3 mask_weights(float2 coord)
{
    int code = mask_code(crt_phosphor_type, int(floor(coord.x)), int(floor(coord.y)));
    if (code < 0) {
        return float3(1.0, 1.0, 1.0);
    }
    float on = 1.0;
    float off = 1.0 - crt_mask_intensity / 100.0;
    float r = code >= 4 ? on : off;
    float g = (code % 4) >= 2 ? on : off;
    float b = (code % 2) == 1 ? on : off;
    return float3(r, g, b);
}

// --- Pass 1: phosphor mask, vignette, rounded corners -------------------------------
float4 PSMask(VertData v_in) : TARGET
{
    float2 coord = v_in.uv * uv_size;
    float4 color = image.Sample(textureSampler, v_in.uv);

    float3 pm_color = mask_weights(coord);

    float2 uv = v_in.uv * (1.0 - v_in.uv);
    float vignette = pow(max(uv.x * uv.y * 15.0, 0.0), crt_vignette / 100.0);

    // Box SDF + rounded corners (https://iquilezles.org/articles/distfunctions2d/)
    float2 d = (abs(coord - uv_size / 2.0) - uv_size / 2.0) + crt_corner_radius;
    float edge_distance = length(max(d, float2(0.0, 0.0))) + min(max(d.x, d.y), 0.0) - crt_corner_radius;
    float aa_mask = 1.0 - smoothstep(-0.7, 0.7, edge_distance);

    return float4(pm_color * color.rgb * vignette, color.a * aa_mask);
}

// --- Bloom ---------------------------------------------------------------------------
float3 threshold_rgb(float3 c)
{
    float lum = dot(c, float3(0.299, 0.587, 0.114));
    return lum > crt_bloom_threshold / 100.0 ? c : float3(0.0, 0.0, 0.0);
}

// Half-size bright pass: threshold each of the 4 source pixels, then average them.
float4 PSBright(VertData v_in) : TARGET
{
    float2 h = float2(upixel, vpixel) * 0.5;
    float3 acc = threshold_rgb(mask.Sample(textureSampler, v_in.uv + float2(-h.x, -h.y)).rgb);
    acc += threshold_rgb(mask.Sample(textureSampler, v_in.uv + float2( h.x, -h.y)).rgb);
    acc += threshold_rgb(mask.Sample(textureSampler, v_in.uv + float2(-h.x,  h.y)).rgb);
    acc += threshold_rgb(mask.Sample(textureSampler, v_in.uv + float2( h.x,  h.y)).rgb);
    return float4(acc * 0.25, 1.0);
}

// Gaussian with sigma = crt_bloom source px (the C kernel spans 3 sigma). Passes are half
// size, so sigma is halved. At most 48 taps per side; the tap spacing grows for big sizes.
float4 PSBlurH(VertData v_in) : TARGET
{
    float sigma = crt_bloom * 0.5;
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
    float sigma = crt_bloom * 0.5;
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

// --- Final pass: bloom combine, barrel distortion, levels -----------------------------
float4 PSComposite(VertData v_in) : TARGET
{
    float dist = crt_barrel_distort * 0.05;
    float2 uv = v_in.uv * 2.0 - 1.0;
    float r_pixel_2 = uv.x * uv.x + uv.y * uv.y;
    float barrel = r_pixel_2 * dist;
    uv = (barrel > EPS) ? 0.5 * ((uv / barrel * (1.0 - sqrt(max(1.0 - 2.0 * barrel, 0.0)))) + 1.0) : v_in.uv;

    // Anti-alias the barrel distortion edges
    float d = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    float w = max(length(float2(ddx(d), ddy(d))), 1.e-6);
    float aa_mask = d < 0.49 ? smoothstep(-0.7, 0.7, (abs(frac(d - 0.25) - 0.5) - 0.25) / w) : 1.0;

    float4 color = mask.Sample(textureSampler, uv);
    if (crt_bloom_intensity > 0.001) {
        // Below 0.01 px the C code skips the blur and adds the thresholded image.
        float3 bloom = crt_bloom < 0.01 ? threshold_rgb(color.rgb) : blurv.Sample(textureSampler, uv).rgb;
        color.rgb += crt_bloom_intensity / 100.0 * bloom;
    }

    float black_level = crt_black_level / 255.0;
    float white_level = crt_white_level / 255.0;
    color.rgb = saturate((color.rgb - black_level) / (white_level - black_level));
    color.a *= aa_mask;
    return color;
}

technique Mask      { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSMask(v_in); } }
technique Bright    { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSBright(v_in); } }
technique BlurH     { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSBlurH(v_in); } }
technique BlurV     { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSBlurV(v_in); } }
technique Composite { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSComposite(v_in); } }
