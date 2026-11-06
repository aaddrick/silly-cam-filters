// Tiny Face Bobblehead: the face shrinks inside the head (hair, ears and cheeks close in around it) and sits on a
// damped spring, so it bobbles and tilts when the head moves, then settles.
// Coordinates: "n" = face-oval units (face frame, centred on the oval, divided by the oval half sizes; the face
// outline is |n| = 1). The warp is radial in n: identity beyond |n| = 1.8, face scaled by head_size inside.
// track (5x1 rgba32f):
//   0: (eyes mid.xy UV, roll, socket distance ISO)    1: (oval centre.xy, oval half size.xy) face-local units
//   2: (spring offset.xy, offset velocity.xy) n units 3: (tilt, tilt velocity, presence, 0)
//   4: (oval centre UV.xy, smoothed velocity ISO/s.xy)
@include "silly_face.hlsl"

uniform float head_size;
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

#define BH_W 12.5        // spring frequency, rad/s (2 Hz)
#define BH_ZETA 0.2      // damping ratio: settles (< 5%) in about 1.2 s
#define BH_OUTER 1.8     // warp reaches identity at 1.8 face-oval radii
#define BH_MAX_OFS 0.3
#define BH_MAX_TILT 0.35

float4 st(float i) { return track_prev.Sample(sf_point_sampler, float2((i + 0.5) / 5.0, 0.5)); }

float4 PSTrack(VertData v_in) : TARGET {
    float idx = floor(v_in.uv.x * 5.0);
    float4 s0 = st(0.0);
    float4 s1 = st(1.0);
    float4 s2 = st(2.0);
    float4 s3 = st(3.0);
    float4 s4 = st(4.0);
    float p_prev = s3.b;
    float p = sf_presence_step(p_prev, 0.3);
    bool ok = sf_face_ok();
    bool fresh = p_prev < 0.01;
    float dt = clamp(delta_time, 0.001, 0.1);
    float a = fresh ? 1.0 : 1.0 - exp(-dt / 0.04);

    float2 c_uv = ok ? sf_face_center() : s4.xy;
    float2 v_raw = (ok && !fresh) ? (sf_to_iso(c_uv) - sf_to_iso(s4.xy)) / dt : float2(0.0, 0.0);
    float2 v = (ok && !fresh) ? lerp(s4.zw, v_raw, 1.0 - exp(-dt / 0.08)) : float2(0.0, 0.0);
    if (idx > 3.5) {
        return float4(c_uv, v);
    }
    if (idx > 1.5) {
        // head acceleration in face-oval units (inertia pushes the face the other way)
        float2 acc_iso = ok ? (v - s4.zw) / dt : float2(0.0, 0.0);
        float unit = max(s0.w * 1.2, 1e-3);
        float2 acc = sf_rotate(acc_iso, -s0.z) / unit * wobble;
        float am = length(acc);
        acc *= smoothstep(1.5, 3.0, am);                 // deadband against landmark jitter
        acc = (am > 60.0) ? acc * (60.0 / am) : acc;
        float h = dt / 4.0;
        float2 o = fresh ? float2(0.0, 0.0) : s2.xy;
        float2 ov = fresh ? float2(0.0, 0.0) : s2.zw;
        float t = fresh ? 0.0 : s3.x;
        float tv = fresh ? 0.0 : s3.y;
        for (int k = 0; k < 4; k++) {
            float2 oa = -BH_W * BH_W * o - 2.0 * BH_ZETA * BH_W * ov - 0.5 * acc;
            ov += oa * h;
            o += ov * h;
            float ta = -BH_W * BH_W * t - 2.0 * BH_ZETA * BH_W * tv + 0.5 * acc.x;
            tv += ta * h;
            t += tv * h;
        }
        float ol = length(o);
        o = (ol > BH_MAX_OFS) ? o * (BH_MAX_OFS / ol) : o;
        t = clamp(t, -BH_MAX_TILT, BH_MAX_TILT);
        if (idx > 2.5) {
            return float4(t, tv, p, 1.0);
        }
        return float4(o, ov);
    }
    if (!ok) {
        return (idx > 0.5) ? s1 : s0;
    }
    if (idx > 0.5) {
        float4 ov = sf_face_oval_local();
        return lerp(s1, ov, a);
    }
    float4 cur = float4(sf_eyes_mid(), sf_roll(), sf_face_scale());
    // roll: lerp the angle difference, not the raw value
    float dr = cur.z - s0.z;
    dr = dr - 6.2831853 * floor((dr + 3.1415927) / 6.2831853);
    return float4(lerp(s0.xy, cur.xy, a), s0.z + dr * a, lerp(s0.w, cur.w, a)) * (fresh ? 0.0 : 1.0)
         + (fresh ? cur : float4(0.0, 0.0, 0.0, 0.0));
}

float4 PSDraw(VertData v_in) : TARGET {
    float4 src = image.Sample(textureSampler, v_in.uv);
    float4 t0 = track.Sample(sf_point_sampler, float2(0.1, 0.5));
    float4 t1 = track.Sample(sf_point_sampler, float2(0.3, 0.5));
    float4 t2 = track.Sample(sf_point_sampler, float2(0.5, 0.5));
    float4 t3 = track.Sample(sf_point_sampler, float2(0.7, 0.5));
    float p = smoothstep(0.0, 1.0, t3.b);
    if (p <= 0.001 || t0.w <= 1e-4) {
        return src;
    }
    float2 mid_iso = sf_to_iso(t0.xy);
    float2 l = sf_rotate(sf_to_iso(v_in.uv) - mid_iso, -t0.z) / t0.w;   // face-local
    float2 h = max(t1.zw, float2(0.05, 0.05));
    float2 n = (l - t1.xy) / h;
    float r = length(n);
    if (r >= BH_OUTER) {
        return src;
    }
    float s = lerp(1.0, head_size, p);
    // the spring moves and tilts the small face; its influence fades out with the warp weight
    float w = 1.0 - smoothstep(s * 1.05, BH_OUTER, r);
    float2 inner = sf_rotate(n - t2.xy * p, -t3.x * p) / s;
    float2 ns = n + w * (inner - n);
    float2 ls = t1.xy + ns * h;
    float2 uv = sf_from_iso(mid_iso + sf_rotate(ls * t0.w, t0.z));
    return image.Sample(textureSampler, uv);
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
