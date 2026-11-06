// Googly Eyes: a white disc over each eye with a black pupil that rolls like a pendulum, driven by
// the head's acceleration (gravity = screen down). State in "track" (4x1 rgba32f):
//   texel 0: (socket L.xy, socket R.xy) UV
//   texel 1: (radius L, radius R, presence, 0) ISO
//   texel 2: (angle L, angular velocity L, angle R, angular velocity R)  angle 0 = hanging straight down
//   texel 3: (face mid.xy UV, smoothed velocity.xy ISO/s)
@include "silly_face.hlsl"

uniform float eye_size;
uniform float pupil_size;
uniform float wobble;
uniform texture2d track;
uniform texture2d track_prev;

sampler_state textureSampler {
    Filter   = Linear;
    AddressU = Clamp;
    AddressV = Clamp;
};

struct VertData {
    float4 pos : POSITION;
    float2 uv  : TEXCOORD0;
};

VertData VSDefault(VertData v_in) {
    VertData vert_out;
    vert_out.pos = mul(float4(v_in.pos.xyz, 1.0), ViewProj);
    vert_out.uv  = v_in.uv;
    return vert_out;
}

#define GE_W0 7.5        // natural swing frequency, rad/s (~1.2 Hz)
#define GE_DAMP 3.5      // damping, 1/s: a swing settles in about 2 s (qa/face_a_self/googly_sim.py)
#define GE_G 5.0         // "gravity" in ISO units/s^2 that the head acceleration competes with

float4 st(float i) { return track_prev.Sample(sf_point_sampler, float2((i + 0.5) / 4.0, 0.5)); }

// one pendulum, semi-implicit Euler in 4 substeps
float2 swing(float2 tw, float2 acc, float w0, float damp, float dt) {
    float h = dt / 4.0;
    for (int k = 0; k < 4; k++) {
        float a = -w0 * w0 * (sin(tw.x) + (acc.x * cos(tw.x) - acc.y * sin(tw.x)) / GE_G) - damp * tw.y;
        tw.y += a * h;
        tw.x += tw.y * h;
    }
    // keep the angle in -pi..pi so it never grows without bound
    tw.x = tw.x - 6.2831853 * floor((tw.x + 3.1415927) / 6.2831853);
    return tw;
}

float4 PSTrack(VertData v_in) : TARGET {
    float idx = floor(v_in.uv.x * 4.0);
    float4 s0 = st(0.0);
    float4 s1 = st(1.0);
    float4 s2 = st(2.0);
    float4 s3 = st(3.0);
    float p_prev = s1.b;
    float p = sf_presence_step(p_prev, 0.3);
    bool ok = sf_face_ok();
    bool fresh = p_prev < 0.01;
    float dt = clamp(delta_time, 0.001, 0.1);

    // head velocity (ISO/s), smoothed ~60 ms; zero while lost or on (re)appearance
    float2 mid = ok ? sf_eyes_mid() : s3.xy;
    float2 v_raw = (ok && !fresh) ? (sf_to_iso(mid) - sf_to_iso(s3.xy)) / dt : float2(0.0, 0.0);
    float2 v = (ok && !fresh) ? lerp(s3.zw, v_raw, 1.0 - exp(-dt / 0.08)) : float2(0.0, 0.0);
    if (idx > 2.5) {
        return float4(mid, v);
    }
    if (idx > 1.5) {
        // accelerating frame: the pupil feels -acceleration
        // no acceleration while the face is lost (the velocity reset is not a real motion)
        float2 acc = ok ? (v - s3.zw) / dt * wobble : float2(0.0, 0.0);
        // deadband: landmark jitter on a still face must not keep the pupils trembling
        float am = length(acc);
        acc *= smoothstep(0.25 * GE_G, 0.5 * GE_G, am);
        float amax = 20.0 * GE_G;
        acc = (length(acc) > amax) ? acc * (amax / length(acc)) : acc;
        if (fresh) {
            return float4(0.0, 0.0, 0.0, 0.0);
        }
        float2 l = swing(s2.xy, acc, GE_W0, GE_DAMP, dt);
        float2 r = swing(s2.zw, acc, GE_W0 * 1.09, GE_DAMP * 0.9, dt);
        return float4(l, r);
    }
    if (!ok) {
        return (idx > 0.5) ? float4(s1.rg, p, 1.0) : s0;
    }
    float a = fresh ? 1.0 : 1.0 - exp(-dt / 0.04);
    if (idx > 0.5) {
        return float4(lerp(s1.rg, float2(sf_eye_l_radius(), sf_eye_r_radius()), a), p, 1.0);
    }
    return lerp(s0, float4(sf_eye_l_socket(), sf_eye_r_socket()), a);
}

// colour of one googly eye at iso point q (relative to the disc centre); alpha = coverage
float4 googly(float2 q, float R, float angle) {
    float aa = 1.5 * vpixel;                      // ~1.5 source px of antialiasing (ISO = vpixel per px)
    float d = length(q);
    float disc = 1.0 - smoothstep(R - aa, R, d);
    if (disc <= 0.0) {
        return float4(0.0, 0.0, 0.0, 0.0);
    }
    // white with a soft grey rim and a light top-left sheen
    float rim = smoothstep(R * 0.80, R, d);
    float3 col = lerp(float3(0.97, 0.97, 0.96), float3(0.72, 0.72, 0.74), rim * rim);
    col += 0.03 * (1.0 - smoothstep(0.0, R, length(q - float2(-0.35, -0.35) * R)));
    float outline = smoothstep(R - 2.5 * aa, R - 1.0 * aa, d);
    col = lerp(col, float3(0.15, 0.15, 0.17), outline);
    // pupil on its pendulum
    float pr = pupil_size * R;
    float L = max(R - pr - 1.5 * aa, 0.0);
    float2 pc = L * float2(sin(angle), cos(angle));
    float dp = length(q - pc);
    float pupil = 1.0 - smoothstep(pr - aa, pr, dp);
    col = lerp(col, float3(0.0, 0.0, 0.0), pupil);
    // highlight on the pupil (fixed, top-left: the light does not move)
    float hl = 1.0 - smoothstep(pr * 0.18 - aa * 0.5, pr * 0.18 + aa * 0.5, length(q - pc - float2(-0.35, -0.38) * pr));
    col = lerp(col, float3(1.0, 1.0, 1.0), hl * pupil * 0.9);
    return float4(col, disc);
}

float4 PSDraw(VertData v_in) : TARGET {
    float4 src = image.Sample(textureSampler, v_in.uv);
    float4 t0 = track.Sample(sf_point_sampler, float2(0.125, 0.5));
    float4 t1 = track.Sample(sf_point_sampler, float2(0.375, 0.5));
    float4 t2 = track.Sample(sf_point_sampler, float2(0.625, 0.5));
    float p = smoothstep(0.0, 1.0, t1.b);
    if (p <= 0.001) {
        return src;
    }
    float half_dist = 0.5 * distance(sf_to_iso(t0.xy), sf_to_iso(t0.zw));
    float2 q = sf_to_iso(v_in.uv);
    float RL = min(eye_size * t1.r, 0.95 * half_dist);
    float RR = min(eye_size * t1.g, 0.95 * half_dist);
    float4 gl = googly(q - sf_to_iso(t0.xy), RL, t2.x);
    float4 gr = googly(q - sf_to_iso(t0.zw), RR, t2.z);
    float4 g = (gl.a > gr.a) ? gl : gr;
    return float4(lerp(src.rgb, g.rgb, g.a * p), src.a);
}

technique Track {
    pass {
        vertex_shader = VSDefault(v_in);
        pixel_shader  = PSTrack(v_in);
    }
}

technique Draw {
    pass {
        vertex_shader = VSDefault(v_in);
        pixel_shader  = PSDraw(v_in);
    }
}
