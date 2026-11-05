// Retro: Digital Glitch
// Port of the Digital Glitch filter from obs-retro-effects 1.0.2 by FiniteSingularity.
// GPL-2.0, as the original.
//
// The original builds three 1D band textures on the CPU (column bands, row bands, and
// color-drift row bands) and rebuilds them after a random interval. Here:
//   glitch_clock: a tiny rgba32f pass that keeps the band "epochs" and the time of the
//                 next update across frames (it reads its own output of the last frame).
//   glitch_out:   rebuilds the same band layout per pixel from a hash seeded with the epoch
//                 (walking the random band sizes from 0, as the C code does), then applies
//                 the original displacement / color-drift shader.

uniform float digital_glitch_amount;
uniform float digital_glitch_max_disp;
uniform int digital_glitch_min_block_width;
uniform int digital_glitch_max_block_width;
uniform int digital_glitch_min_block_height;
uniform int digital_glitch_max_block_height;
uniform float digital_glitch_min_block_interval;
uniform float digital_glitch_max_block_interval;
uniform float digital_glitch_max_rgb_drift;
uniform int digital_glitch_min_rgb_height;
uniform int digital_glitch_max_rgb_height;
uniform float digital_glitch_min_rgb_interval;
uniform float digital_glitch_max_rgb_interval;

uniform float elapsed_time;
uniform float2 uv_size;

// Pass outputs, bound by the engine.
// In the Clock pass, glitch_clock is the pass's own output of the previous frame.
uniform texture2d glitch_clock;

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

// ---------------------------------------------------------------------------
// Clock pass: x = block epoch, y = time of the next block update,
//             z = color-drift epoch, w = time of the next color-drift update.

float4 PSClock(VertData v_in) : TARGET
{
    float4 s = glitch_clock.Sample(pointSampler, v_in.uv);
    float t = elapsed_time;
    float seed = rand_seed * 997.0;

    // First frame (empty texture) or the filter clock restarted: start over.
    if (s.y > t + 5.0 || s.y < -1.0 || s.w > t + 5.0 || s.w < -1.0) {
        s = float4(0.0, -1.0, 0.0, -1.0);
    }

    if (t > s.y) {
        s.x = pmod(s.x + 1.0, 4096.0);
        float r = hash13(float3(s.x, seed, 3.0));
        s.y = t + lerp(digital_glitch_min_block_interval, digital_glitch_max_block_interval, r);
    }
    if (t > s.w) {
        s.z = pmod(s.z + 1.0, 4096.0);
        float r = hash13(float3(s.z, seed, 7.0));
        s.w = t + lerp(digital_glitch_min_rgb_interval, digital_glitch_max_rgb_interval, r);
    }
    return s;
}

// ---------------------------------------------------------------------------
// Glitch pass

// Intensity (0..1) of the band that contains pixel `pos`, for bands laid out from 0
// with random sizes in [min_size, max_size], as in digital_glitch_filter_video_tick().
float band_value(float pos, float min_size, float max_size, float epoch, float salt)
{
    float range = max_size - min_size + 1.0;
    if (range < 1.0) {
        range += 4294967296.0; // the C code does this in uint32 and wraps around
    }
    float start = 0.0;
    for (int k = 0; k < 256; k++) {
        float fk = float(k);
        float intensity = hash13(float3(fk, epoch, salt));
        float r = hash13(float3(fk, epoch, salt + 50.0));
        float size = floor(r * range) + min_size;
        if (pos < start + size) {
            return intensity;
        }
        start += size;
    }
    // Very small bands: continue with bands of the average size.
    float avg = max(1.0, min_size + 0.5 * (range - 1.0));
    float idx = floor((pos - start) / avg);
    return hash13(float3(idx + 256.0, epoch, salt + 100.0));
}

// Map a band intensity to [-1, 1], and to 0 for the bands above the amount.
float band_noise(float intensity, float amount)
{
    float n = 2.0 * intensity - 1.0;
    return abs(n) > amount ? 0.0 : n;
}

float4 PSGlitch(VertData v_in) : TARGET
{
    float4 s = glitch_clock.Sample(pointSampler, float2(0.5, 0.5));
    float block_epoch = s.x;
    float rgb_epoch = s.z;
    float seed = rand_seed * 997.0;
    float amount = digital_glitch_amount / 100.0;

    float2 coord = v_in.uv * uv_size;
    float2 px = floor(coord);

    float n_h = band_value(px.x, float(digital_glitch_min_block_width), float(digital_glitch_max_block_width),
                           block_epoch, seed + 11.0);
    float n_v = band_value(px.y, float(digital_glitch_min_block_height), float(digital_glitch_max_block_height),
                           block_epoch, seed + 23.0);
    float n_rgb = band_value(px.y, float(digital_glitch_min_rgb_height), float(digital_glitch_max_rgb_height),
                             rgb_epoch, seed + 37.0);

    float block_disp = band_noise(n_v, amount) * band_noise(n_h, amount) * digital_glitch_max_disp;
    float rgb_disp = band_noise(n_rgb, amount) * digital_glitch_max_rgb_drift;

    float4 col_r = image.Sample(textureSampler, float2(coord.x + block_disp + rgb_disp, coord.y) / uv_size);
    float4 col_g = image.Sample(textureSampler, float2(coord.x + block_disp, coord.y) / uv_size);
    float4 col_b = image.Sample(textureSampler, float2(coord.x + block_disp - rgb_disp, coord.y) / uv_size);
    float alpha = 0.334 * col_r.a + 0.333 * col_g.a + 0.333 * col_b.a;
    return float4(col_r.r, col_g.g, col_b.b, alpha);
}

technique Clock  { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSClock(v_in); } }
technique Glitch { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSGlitch(v_in); } }
