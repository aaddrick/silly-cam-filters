// Retro: VHS. Port of the VHS filter from obs-retro-effects 1.0.2 by FiniteSingularity
// (GPL-2.0, https://github.com/FiniteSingularity/obs-retro-effects).
//   state:  1x1 rgba32f pass with the random timers of vhs_filter_video_tick
//           (tape wrinkle and frame jitter), updated once per frame
//   result: head switching noise, jitter, tape wrinkle and pop lines (vhs.effect)

uniform float vhs_jitter_min_size;                    // px
uniform float vhs_jitter_max_size;                    // px
uniform float vhs_jitter_min_period;                  // s
uniform float vhs_jitter_max_period;                  // s
uniform float vhs_jitter_min_interval;                // s
uniform float vhs_jitter_max_interval;                // s
uniform float vhs_wrinkle_occurrence;                 // % chance per second
uniform float vhs_wrinkle_size;                       // %
uniform float vhs_wrinkle_duration;                   // s
uniform float vhs_pop_lines_amount;                   // %
uniform float vhs_head_switch_primary_thickness;      // px
uniform float vhs_head_switch_primary_offset;         // px
uniform float vhs_head_switch_secondary_thickness;    // px
uniform float vhs_head_switch_secondary_horiz_offset; // px
uniform float vhs_head_switch_secondary_vert_amount;

uniform float2 uv_size;
uniform float rand_f;

uniform texture2d state;

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

// Hash without sine (Dave Hoskins, MIT). Replaces the pcg-based hash31 of noise-functions.effect.
float hash13(float3 p3)
{
    p3 = frac(p3 * 0.1031);
    p3 += dot(p3, p3.zyx + 31.32);
    return frac((p3.x + p3.y) * p3.z);
}

float frame_rand(float k)
{
    return hash13(float3(rand_f * 4096.0, k * 17.0 + 3.0, float(frame_index % 4096)));
}

// --- Pass 1: timers ----------------------------------------------------------------------
// x: tape wrinkle, 0 = none, else wrinkle position + 0.2 (runs from 1.4 down to 0)
// y: current jitter in px
// z: jitter size in px; > 0 rising, < 0 falling, 0 = no jitter
// w: no jitter: seconds until the next one; jitter: its period in s
// All zeros (the first frame) means: no wrinkle, start a jitter now, as in the C code.
float4 PSState(VertData v_in) : TARGET
{
    float4 s = state.Sample(pointSampler, v_in.uv);
    // Start over on garbage (also catches NaN, for which every comparison is false)
    if (!(s.x >= 0.0 && s.x <= 1.5 && abs(s.y) < 1000.0 && abs(s.z) < 1000.0 && abs(s.w) < 1000.0)) {
        s = float4(0.0, 0.0, 0.0, 0.0);
    }
    float dt = delta_time;

    // Frame jitter
    float cur = s.y;
    float z = s.z;
    float w = s.w;
    if (z != 0.0) {
        float size = abs(z);
        float dir = z > 0.0 ? 1.0 : -1.0;
        float period = max(w, 0.001);
        cur = min(cur + dir * dt * size / period, size);
        if (cur >= size && cur > 0.001) {
            z = -size;
        } else if (cur < 0.001) {
            z = 0.0;
            cur = 0.0;
            w = frame_rand(1.0) * (vhs_jitter_max_interval - vhs_jitter_min_interval) + vhs_jitter_min_interval;
        }
    } else {
        w -= dt;
        if (w < 0.0) {
            float size = frame_rand(2.0) * (vhs_jitter_max_size - vhs_jitter_min_size) + vhs_jitter_min_size;
            float period = frame_rand(3.0) * (vhs_jitter_max_period - vhs_jitter_min_period) + vhs_jitter_min_period;
            cur = 0.0;
            if (size > 0.001) {
                z = size;
                w = period;
            }
        }
    }

    // Tape wrinkle
    float wr = s.x;
    if (wr > 0.0) {
        wr -= dt / max(vhs_wrinkle_duration, 0.01);
        wr = max(wr, 0.0);
    } else if (frame_rand(4.0) < vhs_wrinkle_occurrence / 100.0 * dt) {
        wr = 1.4;
    }

    return float4(wr, cur, z, w);
}

// --- Pass 2: picture ---------------------------------------------------------------------
float4 sample_border(float2 uv)
{
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        return float4(0.0, 0.0, 0.0, 1.0);
    }
    return image.Sample(textureSampler, uv);
}

float4 PSEffect(VertData v_in) : TARGET
{
    float4 s = state.Sample(pointSampler, float2(0.5, 0.5));
    float wrinkle_position = s.x > 0.0 ? s.x - 0.2 : -10.0;
    float horizontal_offset = s.y;
    float wrinkle_size = vhs_wrinkle_size / 100.0;
    float pop_line_prob = vhs_pop_lines_amount / (100.0 * 1000.0);
    float t = float(frame_index % 8192);

    float hs_primary_thickness = vhs_head_switch_primary_thickness;
    float hs_primary_offset = vhs_head_switch_primary_offset;
    float hs_secondary_thickness = vhs_head_switch_secondary_thickness;
    float hs_secondary_horiz_offset = vhs_head_switch_secondary_horiz_offset;
    float hs_secondary_vert_offset = -hs_secondary_thickness + vhs_head_switch_secondary_vert_amount * hs_primary_offset;

    float2 coord = v_in.uv * uv_size;

    // Head switching noise at the bottom of the frame
    float hs_shift = step(uv_size.y - hs_primary_thickness, coord.y) * hs_primary_offset;
    float hs_top = uv_size.y - (hs_primary_thickness + hs_secondary_thickness + hs_secondary_vert_offset);
    float hs_secondary_shift = step(hs_top, coord.y) * (1.0 - smoothstep(hs_top, hs_top + hs_secondary_thickness, coord.y)) * hs_secondary_horiz_offset;
    coord.x -= hs_shift + hs_secondary_shift;
    float2 sample_uv = (coord + float2(horizontal_offset, 0.0)) / uv_size;

    // Tape wrinkle: a band that repeats one line of the picture
    float transition = 0.20 * wrinkle_size;
    float ss_1 = smoothstep(wrinkle_position - wrinkle_size, wrinkle_position - wrinkle_size + transition, v_in.uv.y);
    float ss_2 = 1.0 - smoothstep(wrinkle_position + wrinkle_size - transition, wrinkle_position + wrinkle_size, v_in.uv.y);
    float weight = ss_1 * ss_2;

    float4 color = (1.0 - weight) * sample_border(sample_uv) + weight * sample_border(float2(sample_uv.x, wrinkle_position));

    // Pop lines: random white streaks
    float pop_line = hash13(float3(0.0, coord.y, t));
    if (pop_line < pop_line_prob) {
        pop_line = hash13(float3(coord.xy, t));
        color = color * (1.0 - pop_line) + float4(1.0, 1.0, 1.0, color.a) * pop_line;
    }
    return color;
}

technique State { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSState(v_in); } }
technique Draw  { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSEffect(v_in); } }
