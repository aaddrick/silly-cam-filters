// Retro: Matrix Rain
// Port of the Matrix Rain filter from obs-retro-effects 1.0.2 by FiniteSingularity.
// GPL-2.0, as the original.
//
// Passes:
//   mr_rain:   the original matrix-rain shader.
//   mr_bright: bloom brightness threshold (the original always uses 0.4).
//   mr_blur_h: horizontal gaussian, sigma = matrix_bloom_radius px, reach 3 sigma.
//   mr_out:    vertical gaussian + additive bloom combine.
//
// The original's uint PCG / murmur hashes are replaced by float hashes, so the characters and
// column speeds are random in the same way but not the same values.

uniform int matrix_char_set;
uniform texture2d matrix_rain_texture;
uniform float2 matrix_rain_texture_size;
uniform int matrix_rain_texture_chars;
uniform texture2d matrix_font_matrix;
uniform float2 matrix_font_matrix_size;
uniform texture2d matrix_font_ascii70;
uniform float2 matrix_font_ascii70_size;
uniform texture2d matrix_font_ascii10;
uniform float2 matrix_font_ascii10_size;
uniform texture2d matrix_font_emojis;
uniform float2 matrix_font_emojis_size;

uniform float matrix_rain_scale;
uniform float matrix_rain_noise_shift;
uniform bool matrix_rain_colorize;
uniform float4 matrix_rain_text_color;
uniform float4 matrix_rain_background_color;
uniform float matrix_min_brightness;
uniform float matrix_max_brightness;
uniform float matrix_min_fade_value;
uniform float matrix_active_rain_brightness;
uniform float matrix_fade_distance;
uniform float matrix_speed_factor;
uniform float matrix_bloom_radius;
uniform float matrix_bloom_threshold;
uniform float matrix_bloom_intensity;

uniform float2 uv_size;
uniform float elapsed_time;
uniform float2 pass_texel;

// Pass outputs, bound by the engine
uniform texture2d mr_rain;
uniform texture2d mr_bright;
uniform texture2d mr_blur_h;

#define EPS 1.e-6
// obs-retro-effects sets the bloom threshold to 0.4 on every frame, whatever the setting.
#define BLOOM_THRESHOLD 0.4

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

float pmod(float x, float y)
{
    return x - y * floor(x / y);
}

// Dave Hoskins' "hash without sine", 3 in -> 1 out, [0, 1)
float hash13(float3 p3)
{
    p3 = frac(p3 * 0.1031);
    p3 += dot(p3, p3.zyx + 31.32);
    return frac((p3.x + p3.y) * p3.z);
}

float gray(float3 col)
{
    return col.r * 0.299 + col.g * 0.587 + col.b * 0.114;
}

// ---------------------------------------------------------------------------
// Rain

// The selected character atlas: (width, height, number of characters)
float3 font_info()
{
    if (matrix_char_set == 0 && matrix_rain_texture_size.x >= 1.0) {
        return float3(matrix_rain_texture_size, max(float(matrix_rain_texture_chars), 1.0));
    }
    if (matrix_char_set == 2) {
        return float3(matrix_font_ascii70_size, 33.0);
    }
    if (matrix_char_set == 3) {
        return float3(matrix_font_ascii10_size, 10.0);
    }
    if (matrix_char_set == 4) {
        return float3(matrix_font_emojis_size, 52.0);
    }
    // Set 1, and Custom without a texture
    return float3(matrix_font_matrix_size, 56.0);
}

float4 sample_font(float2 uv)
{
    if (matrix_char_set == 0 && matrix_rain_texture_size.x >= 1.0) {
        return matrix_rain_texture.Sample(textureSampler, uv);
    }
    if (matrix_char_set == 2) {
        return matrix_font_ascii70.Sample(textureSampler, uv);
    }
    if (matrix_char_set == 3) {
        return matrix_font_ascii10.Sample(textureSampler, uv);
    }
    if (matrix_char_set == 4) {
        return matrix_font_emojis.Sample(textureSampler, uv);
    }
    return matrix_font_matrix.Sample(textureSampler, uv);
}

float4 PSRain(VertData v_in) : TARGET
{
    // The original's local_time (speed-scaled seconds since the filter was created).
    // Stateless: changing the speed makes the rain jump instead of changing pace smoothly.
    float local_time = elapsed_time * matrix_speed_factor;

    float3 info = font_info();
    float num_chars = info.z;
    float char_height = max(info.y, 1.0);
    float char_width = max(info.x / num_chars, 0.001);
    float scale = max(matrix_rain_scale, 0.0001);
    float fade_distance = max(matrix_fade_distance, 0.001);
    float noise_shift = matrix_rain_noise_shift;

    float2 coord = v_in.uv * uv_size;
    float2 cell_size = float2(char_width, char_height) * scale;

    // Top-left corner of the character cell, in pixels and in UV
    float2 cell_px = floor(coord / cell_size) * cell_size;
    float2 uv = cell_px / uv_size;

    float char_noise = hash13(float3(floor(cell_px.x + noise_shift), floor(cell_px.y), 1.0));
    float rotation_speed = hash13(float3(floor(cell_px.x), floor(cell_px.y), 10.0));

    float noise_shift_px = floor(noise_shift / cell_size.x) * cell_size.x;
    float2 sub_pos = frac(coord / cell_size);

    // One random speed per column (the original's rain_phase is unused)
    float column_x = floor(cell_px.x - noise_shift_px + 0.5);
    float rain_speed = 1.0 + hash13(float3(column_x, 0.0, 12345.0)) * 7.0;

    float rainY = frac(local_time / rain_speed);
    float rainY_px = rainY * uv_size.y;
    float rain_uv = (floor(rainY_px / cell_size.y) * cell_size.y) / uv_size.y;
    float rain = abs(uv.y - rain_uv) < 0.002 ? 1.0 : 0.0;

    float rain_scale = 1.0;
    if (uv.y >= rain_uv) {
        rain_scale = uv.y - rain_uv;
    } else {
        rain_scale = 1.0 - (rain_uv - uv.y);
    }
    rain_scale = rain_scale / fade_distance - (1.0 / fade_distance - 1.0);
    rain_scale = rain_scale * (1.0 - matrix_min_fade_value) + matrix_min_fade_value;
    rotation_speed = rotation_speed * (9.0 * rain + 1.0);

    float4 col = image.Sample(textureSampler, uv);
    if (col.a < EPS) {
        return float4(0.0, 0.0, 0.0, 0.0);
    }

    float g = min(gray(col.rgb), 0.99);
    float brightness_range = matrix_max_brightness - matrix_min_brightness;
    if (abs(brightness_range) < 0.0001) {
        brightness_range = 0.0001;
    }
    rain_scale *= (g / brightness_range + matrix_min_brightness);

    float char_index = pmod(floor(char_noise * num_chars) + floor(rotation_speed * local_time), num_chars);
    float char_u = char_index / num_chars;
    float2 sample_uv = float2(char_u, 0.0) + float2(1.0 / num_chars, 1.0) * sub_pos;

    float4 cha = sample_font(sample_uv);
    cha = float4(1.0 - cha.r, 1.0 - cha.g, 1.0 - cha.b, 1.0 - gray(cha.rgb));

    float4 pixel = matrix_rain_text_color;
    if (matrix_rain_colorize) {
        pixel = float4(col.rgb / max(max(col.r, max(col.g, col.b)), EPS), col.a);
    }
    if (rain > 0.5) {
        pixel = pixel * (1.0 - matrix_active_rain_brightness) + float4(1.0, 1.0, 1.0, pixel.a) * matrix_active_rain_brightness;
        rain_scale = 1.0;
    }
    float4 out_col = cha * rain_scale * pixel + (1.0 - cha * rain_scale) * matrix_rain_background_color;
    return saturate(out_col);
}

// ---------------------------------------------------------------------------
// Bloom

float4 PSBright(VertData v_in) : TARGET
{
    float4 color = mr_rain.Sample(textureSampler, v_in.uv);
    float lum = dot(color.rgb, float3(0.299, 0.587, 0.114));
    return lum > BLOOM_THRESHOLD ? color : float4(0.0, 0.0, 0.0, color.a);
}

// Gaussian with sigma = matrix_bloom_radius pixels and a reach of 3 sigma, as the original's
// kernel. Two texels per sample (linear filtering), up to 32 samples on each side (128 px).
float4 gaussian_bright(float2 uv, float2 dir)
{
    float sigma = matrix_bloom_radius;
    float4 acc = mr_bright.Sample(textureSampler, uv);
    if (sigma < 0.01) {
        return acc;
    }
    float reach = ceil(3.0 * sigma);
    float inv2s2 = 1.0 / (2.0 * sigma * sigma);
    float total = 1.0;
    for (int k = 0; k < 32; k++) {
        float o1 = float(2 * k + 1);
        if (o1 > reach) {
            break;
        }
        float o2 = o1 + 1.0;
        float w1 = exp(-o1 * o1 * inv2s2);
        float w2 = o2 > reach ? 0.0 : exp(-o2 * o2 * inv2s2);
        float w = w1 + w2;
        float o = (o1 * w1 + o2 * w2) / w;
        acc += mr_bright.SampleLevel(textureSampler, uv + dir * o, 0.0) * w;
        acc += mr_bright.SampleLevel(textureSampler, uv - dir * o, 0.0) * w;
        total += 2.0 * w;
    }
    return acc / total;
}

float4 gaussian_blur_h(float2 uv, float2 dir)
{
    float sigma = matrix_bloom_radius;
    float4 acc = mr_blur_h.Sample(textureSampler, uv);
    if (sigma < 0.01) {
        return acc;
    }
    float reach = ceil(3.0 * sigma);
    float inv2s2 = 1.0 / (2.0 * sigma * sigma);
    float total = 1.0;
    for (int k = 0; k < 32; k++) {
        float o1 = float(2 * k + 1);
        if (o1 > reach) {
            break;
        }
        float o2 = o1 + 1.0;
        float w1 = exp(-o1 * o1 * inv2s2);
        float w2 = o2 > reach ? 0.0 : exp(-o2 * o2 * inv2s2);
        float w = w1 + w2;
        float o = (o1 * w1 + o2 * w2) / w;
        acc += mr_blur_h.SampleLevel(textureSampler, uv + dir * o, 0.0) * w;
        acc += mr_blur_h.SampleLevel(textureSampler, uv - dir * o, 0.0) * w;
        total += 2.0 * w;
    }
    return acc / total;
}

float4 PSBlurH(VertData v_in) : TARGET
{
    return gaussian_bright(v_in.uv, float2(pass_texel.x, 0.0));
}

float4 PSCombine(VertData v_in) : TARGET
{
    float4 color = mr_rain.Sample(textureSampler, v_in.uv);
    float4 bloom = gaussian_blur_h(v_in.uv, float2(0.0, pass_texel.y));
    return float4(color.rgb + matrix_bloom_intensity * bloom.rgb, color.a);
}

technique Rain    { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSRain(v_in); } }
technique Bright  { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSBright(v_in); } }
technique BlurH   { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSBlurH(v_in); } }
technique Combine { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSCombine(v_in); } }
