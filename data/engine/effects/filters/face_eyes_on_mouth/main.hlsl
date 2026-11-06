// Eyes on Mouth: each eye spot shows the mouth (so the "eyes" talk), and the mouth spot shows both eyes with their brows,
// uniformly scaled (no squashing) and soft-edged. All in the rolled face frame ("local": origin = eye-socket midpoint,
// unit = socket distance; the sockets are at (-0.5, 0) and (0.5, 0)), so it follows roll and scale.
// track (3x1 rgba32f): 0 = (eyes mid.xy UV, roll, socket distance ISO), 1 = (mouth centre.xy local, mouth half width local,
// eye half width local), 2 = (presence, 0, 0, 1). Kept while the face is lost, so the effect fades out in place.
@include "silly_face.hlsl"

uniform float softness;
uniform float patch_size;
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
        float sc = max(sf_face_scale(), 1e-4);
        float4 cur1 = float4(sf_to_local(sf_mouth_center()), 0.5 * sf_mouth_width() / sc,
                             0.5 * (sf_eye_l_radius() + sf_eye_r_radius()) / sc);
        return fresh ? cur1 : lerp(s1, cur1, a);
    }
    float4 cur = float4(sf_eyes_mid(), sf_roll(), sf_face_scale());
    float dr = cur.z - s0.z;
    dr = dr - 6.2831853 * floor((dr + 3.1415927) / 6.2831853);
    float4 sm = float4(lerp(s0.xy, cur.xy, a), s0.z + dr * a, lerp(s0.w, cur.w, a));
    return fresh ? cur : sm;
}

// The mouth shown at each eye is stretched vertically (cartoon "mouth eyes": lips and teeth read as a mouth, not a slit).
#define FM_EYE_STRETCH_INV 0.6

// weight of a target ellipse at local point l, and the source point it shows (uniform scale k about the source centre)
float patch_w(float2 l, float2 c, float2 semi) {
    float d = length((l - c) / semi);
    return 1.0 - smoothstep(1.0 - softness, 1.0, d);
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
    float2 l = sf_rotate(sf_to_iso(v_in.uv) - mid_iso, -t0.z) / t0.w;
    float2 mouth_c = t1.xy;
    float mouth_hw = clamp(t1.z, 0.2, 0.6);
    float eye_hw = clamp(t1.w, 0.12, 0.35);

    // targets: eye spots (eye + lids) and the mouth spot (lips)
    // fix r2 (D36, cartoon not uncanny): rounder, taller eye spots that show the WHOLE lips (source half height
    // ~0.95 mouth half widths, not a teeth slit), and a mouth spot 1.4x bigger so the eyes on the mouth read.
    float2 eye_semi = float2(1.7, 1.2) * eye_hw * patch_size;
    float2 mouth_semi = float2(1.82, 1.12) * mouth_hw * patch_size;
    // sources: the mouth (for the eyes) and the eye band with brows (for the mouth), uniformly scaled to fit
    float k_eye = (1.35 * mouth_hw) / (1.7 * eye_hw);            // source/target scale for an eye spot
    float k_mouth = (0.5 + 1.6 * eye_hw) / (1.82 * mouth_hw);    // eye band half width / mouth spot half width

    float2 el = float2(-0.5, 0.0);
    float2 er = float2(0.5, 0.0);
    float wl = patch_w(l, el, eye_semi);
    float wr = patch_w(l, er, eye_semi);
    float wm = patch_w(l, mouth_c, mouth_semi);

    float2 ls = l;
    float w = 0.0;
    if (wl > 0.0) {
        ls = mouth_c + (l - el) * k_eye * float2(1.0, FM_EYE_STRETCH_INV);
        w = wl;
    } else if (wr > 0.0) {
        ls = mouth_c + (l - er) * k_eye * float2(1.0, FM_EYE_STRETCH_INV);
        w = wr;
    } else if (wm > 0.0) {
        // centre the eye band slightly above the socket line so the brows come along
        ls = float2(0.0, -0.08) + (l - mouth_c) * k_mouth;
        w = wm;
    }
    if (w <= 0.0) {
        return src;
    }
    float2 uv = sf_from_iso(mid_iso + sf_rotate(ls * t0.w, t0.z));
    float4 sw = image.Sample(textureSampler, uv);
    return float4(lerp(src.rgb, sw.rgb, w * p), src.a);
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
