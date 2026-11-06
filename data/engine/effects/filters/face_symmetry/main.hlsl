// Perfect Symmetry: one half of the face is replaced by the mirror image of the other half, mirrored across the
// eye-corner midline (the perpendicular bisector of the two eye sockets, so it follows roll and does not move with gaze).
// The mirror maps the midline onto itself, so the seam is continuous; "blend" softens it further. The effect covers the
// face oval (landmarks 10/152/234/454) and feathers out between 1.0 and 1.15 oval radii, fading above the brows.
// track (3x1 rgba32f): 0 = (eyes mid.xy UV, roll, socket distance ISO), 1 = (oval centre.xy, half size.xy) face-local,
//                      2 = (presence, 0, 0, 1). Kept while the face is lost, so the effect fades out in place.
@include "silly_face.hlsl"

uniform int side;
uniform float blend;
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

float4 st(float i) { return track_prev.Sample(sf_point_sampler, float2((i + 0.5) / 3.0, 0.5)); }

float4 PSTrack(VertData v_in) : TARGET {
    float idx = floor(v_in.uv.x * 3.0);
    float4 s0 = st(0.0);
    float4 s1 = st(1.0);
    float p_prev = st(2.0).r;
    float p = sf_presence_step(p_prev, 0.3);
    if (idx > 1.5) {
        return float4(p, 0.0, 0.0, 1.0);
    }
    if (!sf_face_ok()) {
        return (idx > 0.5) ? s1 : s0;
    }
    bool fresh = p_prev < 0.01;
    float a = fresh ? 1.0 : 1.0 - exp(-clamp(delta_time, 0.001, 0.1) / 0.04);
    if (idx > 0.5) {
        return lerp(s1, sf_face_oval_local(), a);
    }
    float4 cur = float4(sf_eyes_mid(), sf_roll(), sf_face_scale());
    float dr = cur.z - s0.z;
    dr = dr - 6.2831853 * floor((dr + 3.1415927) / 6.2831853);
    float4 sm = float4(lerp(s0.xy, cur.xy, a), s0.z + dr * a, lerp(s0.w, cur.w, a));
    return fresh ? cur : sm;
}

float4 PSDraw(VertData v_in) : TARGET {
    float4 src = image.Sample(textureSampler, v_in.uv);
    float4 t0 = track.Sample(sf_point_sampler, float2(1.0 / 6.0, 0.5));
    float4 t1 = track.Sample(sf_point_sampler, float2(0.5, 0.5));
    float p = smoothstep(0.0, 1.0, track.Sample(sf_point_sampler, float2(5.0 / 6.0, 0.5)).r);
    if (p <= 0.001 || t0.w <= 1e-4) {
        return src;
    }
    float2 mid_iso = sf_to_iso(t0.xy);
    float2 l = sf_rotate(sf_to_iso(v_in.uv) - mid_iso, -t0.z) / t0.w;     // face-local, x = 0 on the midline
    float2 h = max(t1.zw, float2(0.05, 0.05));
    float d = length((l - t1.xy) / h);
    // fix r2 (D9 ghosts): feather just outside the oval (1.0-1.15 radii, was 1.05-1.3), so little mirrored hair, ear or background lands outside the
    // face, and fade the mirror out above the brows (face-local y < -0.45 eye distances), where hair and partings
    // make a mirrored forehead look smeared.
    // Above the eyes, the replaced side's temple also stays original (|x| > 0.5..0.9 eye distances, above y -0.2..-0.4): with the head turned a
    // little, the far temple's hair and shadow would otherwise be mirrored onto the near forehead (the side=right ghost).
    float temple = (1.0 - smoothstep(-0.4, -0.2, l.y)) * smoothstep(0.5, 0.9, abs(l.x));
    float region = (1.0 - smoothstep(1.0, 1.15, d)) * smoothstep(-0.85, -0.45, l.y) * (1.0 - temple);
    if (region <= 0.0) {
        return src;
    }
    // x on the kept side is positive; mirror the other side
    float sx = (side == 1) ? l.x : -l.x;
    float w = smoothstep(-blend, blend, -sx);                 // 1 = fully mirrored (the replaced side)
    if (blend <= 0.0) {
        w = (sx < 0.0) ? 1.0 : 0.0;
    }
    float2 lm = float2(-l.x, l.y);
    float2 uv_m = sf_from_iso(mid_iso + sf_rotate(lm * t0.w, t0.z));
    float4 mir = image.Sample(textureSampler, uv_m);
    return float4(lerp(src.rgb, mir.rgb, w * region * p), src.a);
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
