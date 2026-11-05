// Retro: NTSC. Port of the NTSC filter from obs-retro-effects 1.0.2 by FiniteSingularity
// (GPL-2.0, https://github.com/FiniteSingularity/obs-retro-effects).
//   state:  1x1 rgba32f pass that keeps the vertical roll offset across frames
//           (the C code's ntsc_filter_video_tick)
//   encode: RGB -> NTSC-like signal: luma, chroma amplitude, chroma phase (ntsc-encode.effect)
//   decode: luma banding, chroma bleed, brightness/saturation, back to RGB (ntsc-decode.effect)

uniform float ntsc_tuning_offset;
uniform float ntsc_luma_noise;            // %
uniform float ntsc_luma_band_size;        // px
uniform float ntsc_luma_band_strength;    // %
uniform int   ntsc_luma_band_count;
uniform float ntsc_chroma_bleed_size;     // px
uniform int   ntsc_chroma_bleed_steps;
uniform float ntsc_chroma_bleed_strength; // %
uniform float ntsc_brightness;            // %
uniform float ntsc_saturation;            // %

uniform float2 uv_size;

uniform texture2d state;
uniform texture2d encode;

#define PI  3.1415926535
#define TAU 6.2831853071

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

float fmod_pos(float x, float y)
{
    return x - y * floor(x / y);
}

// Hash without sine (Dave Hoskins, MIT). Replaces the pcg-based hash31 of noise-functions.effect.
float hash13(float3 p3)
{
    p3 = frac(p3 * 0.1031);
    p3 += dot(p3, p3.zyx + 31.32);
    return frac((p3.x + p3.y) * p3.z);
}

// --- Pass 1: roll offset state ---------------------------------------------------------
// x = y_offset in pixels. Same per-frame update as ntsc_filter_video_tick.
float4 PSState(VertData v_in) : TARGET
{
    float y_offset = state.Sample(pointSampler, v_in.uv).x;
    float height = uv_size.y * 1.10;
    // Start over on garbage (also catches NaN, for which every comparison is false)
    if (!(y_offset >= 0.0 && y_offset <= height)) {
        y_offset = 0.0;
    }
    if (ntsc_tuning_offset <= 20.0) {
        y_offset = floor(y_offset / 1.8);
    } else {
        y_offset += (ntsc_tuning_offset - 20.0) * (height / 400.0);
        y_offset = fmod_pos(y_offset, height);
    }
    return float4(y_offset, 0.0, 0.0, 1.0);
}

// --- Pass 2: encode ---------------------------------------------------------------------
float3 rgb2yiq(float3 c)
{
    return float3(
        dot(c, float3(0.2979,  0.5870,  0.1140)),
        dot(c, float3(0.5959, -0.2744, -0.3216)),
        dot(c, float3(0.2115, -0.5229,  0.3114))
    );
}

float4 PSEncode(VertData v_in) : TARGET
{
    float frame = float(frame_index % 8192);
    float y_offset = max(0.0, state.Sample(pointSampler, float2(0.5, 0.5)).x - 20.0);

    // 10% black bar at the top/bottom and 5% at the left/right while the picture rolls.
    float height = uv_size.y * 1.10;
    float width = uv_size.x * 1.05;

    float2 coord = v_in.uv * uv_size;

    float noise = hash13(float3(1.0, coord.y, frame));

    // Tuning error offsets/smears each line horizontally
    float tuning_error = abs(ntsc_tuning_offset) < 900.0 ? noise * ntsc_tuning_offset : noise * (900.0 + (ntsc_tuning_offset - 900.0) * 10.0);
    tuning_error = noise < 0.996 ? tuning_error : tuning_error * 3.1;

    float2 offset_coord = coord + float2(tuning_error, y_offset);
    offset_coord.y = fmod_pos(offset_coord.y, height);
    offset_coord.x = fmod_pos(offset_coord.x, width);

    float2 suv = offset_coord / uv_size;
    float4 color = float4(0.0, 0.0, 0.0, 1.0);   // border color of the C sampler
    if (suv.x >= 0.0 && suv.x <= 1.0 && suv.y >= 0.0 && suv.y <= 1.0) {
        color = image.Sample(textureSampler, suv);
    }
    float3 yiq = rgb2yiq(color.rgb);

    // Luma noise
    yiq.x += 2.0 * (hash13(float3(coord + 2000.0, frame)) - 0.5) * (ntsc_luma_noise / 100.0);

    // x: luma, y: chroma amplitude (saturation), z: chroma phase (hue), 0..1
    float saturation = length(yiq.yz);
    float phase_shift = (atan2(yiq.z, yiq.y) + PI) / TAU;
    float3 ntsc = float3(yiq.x, saturation, phase_shift);

    // Tuning error pulls luma towards noise and drops the chroma
    float signal_error = hash13(float3(coord, frame + 4096.0)) * abs(ntsc_tuning_offset) / 1000.0;
    ntsc.x = ntsc.x * (1.0 - abs(ntsc_tuning_offset) / 1000.0) + abs(signal_error);
    ntsc.yz *= 1.0 - saturate(abs(ntsc_tuning_offset) / 500.0);
    // The C code stores this in an 8-bit texture, which clamps to 0..1.
    return saturate(float4(ntsc, color.a));
}

// --- Pass 3: decode ---------------------------------------------------------------------
float3 yiq2rgb(float3 c)
{
    return float3(
        dot(c, float3(1.0,  0.9560,  0.6210)),
        dot(c, float3(1.0, -0.2720, -0.6474)),
        dot(c, float3(1.0, -1.1060,  1.7046))
    );
}

float decay_wave(float x, float cycles)
{
    float x2 = x * PI * cycles;
    return cos(x2) * (1.0 - x);
}

float4 PSDecode(VertData v_in) : TARGET
{
    float luma_band_strength = ntsc_luma_band_strength / 400.0;
    float luma_band_cycles = float(ntsc_luma_band_count * 2 + 1);
    float chroma_bleed_strength = ntsc_chroma_bleed_strength / 100.0;
    int chroma_steps = max(ntsc_chroma_bleed_steps, 1);

    float2 coord = v_in.uv * uv_size;
    float4 ntsc = encode.Sample(textureSampler, v_in.uv);
    ntsc.z = ntsc.z * TAU - PI;

    // Luma banding: decaying cos wave convolution around high contrast areas
    float luma_band = ntsc.x;
    float luma_coef_sum = 1.0;
    for (int i = 1; i <= 100; i++) {
        if (float(i) > ntsc_luma_band_size) break;
        float2 stp = float2(float(i), 0.0);
        float l1 = encode.Sample(textureSampler, (coord + stp) / uv_size).x;
        float l2 = encode.Sample(textureSampler, (coord - stp) / uv_size).x;
        float coef = decay_wave(float(i) / ntsc_luma_band_size, luma_band_cycles);
        luma_coef_sum += coef * 2.0;
        luma_band += (l1 + l2) * coef;
    }
    luma_band /= luma_coef_sum;
    ntsc.x = (1.0 - luma_band_strength) * ntsc.x + luma_band_strength * luma_band;

    // Chroma bleed: smoothstep convolution of amplitude and phase
    float chroma_coef_sum = 1.0;
    float2 chroma_bleed = ntsc.yz;
    float step_size = ntsc_chroma_bleed_size / float(chroma_steps);
    for (int j = 1; j <= 30; j++) {
        if (j > chroma_steps) break;
        float2 stp = float2(float(j) * step_size, 0.0);
        float2 c1 = encode.Sample(textureSampler, (coord + stp) / uv_size).yz;
        float2 c2 = encode.Sample(textureSampler, (coord - stp) / uv_size).yz;
        c1.y = c1.y * TAU - PI;
        c2.y = c2.y * TAU - PI;
        float coef = smoothstep(0.0, 1.0, 1.0 - float(j) / float(chroma_steps));
        chroma_coef_sum += coef * 2.0;
        chroma_bleed += (c1 + c2) * coef;
    }
    chroma_bleed /= chroma_coef_sum;
    ntsc.yz = (1.0 - chroma_bleed_strength) * ntsc.yz + chroma_bleed_strength * chroma_bleed;

    // Receiver brightness and saturation
    ntsc.x *= ntsc_brightness / 100.0;
    ntsc.y *= ntsc_saturation / 100.0;

    float3 yiq = float3(ntsc.x, cos(ntsc.z) * ntsc.y, sin(ntsc.z) * ntsc.y);
    return float4(yiq2rgb(yiq), ntsc.a);
}

technique State  { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSState(v_in); } }
technique Encode { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSEncode(v_in); } }
technique Decode { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSDecode(v_in); } }
