// Big Eyes: magnify each eye with a smooth radial bulge centred on the eye socket.
// Pass "track" (2x1 rgba32f) keeps the eye positions and a presence value, so the effect fades out
// over ~0.3 s on the last known eye positions when the face is lost, and fades in on detection.
//   texel 0: (socket L.xy, socket R.xy) UV     texel 1: (radius L, radius R, presence, 0) ISO
@include "silly_face.hlsl"

uniform float size;
uniform float strength;
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

float4 PSTrack(VertData v_in) : TARGET {
    bool first = v_in.uv.x < 0.5;
    float4 prev0 = track_prev.Sample(sf_point_sampler, float2(0.25, v_in.uv.y));
    float4 prev1 = track_prev.Sample(sf_point_sampler, float2(0.75, v_in.uv.y));
    float p_prev = prev1.b;
    float p = sf_presence_step(p_prev, 0.3);
    if (!sf_face_ok()) {
        // keep the last eye positions while fading out
        return first ? prev0 : float4(prev1.rg, p, 1.0);
    }
    float4 cur0 = float4(sf_eye_l_socket(), sf_eye_r_socket());
    float4 cur1 = float4(sf_eye_l_radius(), sf_eye_r_radius(), p, 1.0);
    // light smoothing against landmark jitter (~40 ms); snap when the face (re)appears
    float a = (p_prev < 0.01) ? 1.0 : 1.0 - exp(-delta_time / 0.04);
    if (first) {
        return lerp(prev0, cur0, a);
    }
    return float4(lerp(prev1.rg, cur1.rg, a), p, 1.0);
}

// Eye bulge, v2 (taste fix): an ellipse aligned with the eye axis, short vertically (1.15 eye half-widths, so the brows
// stay outside it), longer on the temple side (3.0) than on the nose side (2.1, capped by the other eye). Radial in the
// normalized ellipse: flat magnification 1/(1-strength) inside 0.4 of it, smoothstep back to identity at its edge.
// Monotonic (no fold) for strength < 1. At the defaults: 2.0x at the centre, ~1.8x across the eye opening, 1.7x at the
// outer corner, 1.4x at the inner corner.
float2 big_eye_uv(float2 uv, float2 c, float r_eye, float max_nose, float2 axis, float temple_sign) {
    float2 d = sf_to_iso(uv) - sf_to_iso(c);
    float u = dot(d, axis);
    float v = dot(d, float2(-axis.y, axis.x));
    float hw = max(r_eye, 1e-5);
    float rx = (u * temple_sign > 0.0) ? 3.0 * hw * size : min(2.1 * hw * size, max_nose);
    float ry = 1.15 * hw * size;
    float r = length(float2(u / max(rx, 1e-5), v / max(ry, 1e-5)));
    if (r >= 1.0) {
        return uv;
    }
    float k = 1.0 - strength * (1.0 - smoothstep(0.4, 1.0, r));
    return sf_from_iso(sf_to_iso(c) + d * k);
}

float4 PSDraw(VertData v_in) : TARGET {
    float4 src = image.Sample(textureSampler, v_in.uv);
    float4 t0 = track.Sample(sf_point_sampler, float2(0.25, 0.5));
    float4 t1 = track.Sample(sf_point_sampler, float2(0.75, 0.5));
    float p = t1.b;
    if (p <= 0.001) {
        return src;
    }
    float2 cl = t0.xy;
    float2 cr = t0.zw;
    float2 dlr = sf_to_iso(cr) - sf_to_iso(cl);
    float half_dist = 0.5 * length(dlr);
    float2 axis = dlr / max(2.0 * half_dist, 1e-6);
    // inner (nose-side) reach stops short of the midpoint between the eyes, so the bulges never overlap
    float2 uv = big_eye_uv(v_in.uv, cl, t1.r, 0.95 * half_dist, axis, -1.0);
    uv = big_eye_uv(uv, cr, t1.g, 0.95 * half_dist, axis, 1.0);
    float s = smoothstep(0.0, 1.0, p);
    // fade the warp itself (not a cross-dissolve), so there is no ghosting
    uv = lerp(v_in.uv, uv, s);
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
