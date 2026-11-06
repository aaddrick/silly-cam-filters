// silly_face.hlsl -- shared face-landmark helpers for Silly Cam Filters folder effects.
// Use:  @include "silly_face.hlsl"   in main.hlsl, with this parameter in meta.json:
//   { "type": "facetracking", "name": "fd", "use_preraster": true }
// Do not declare fd_face_found / fd_bbox_tl / fd_bbox_br / fd_points_tex / fd_preraster_tex yourself.
// Conventions (see docs/ENGINE.md):
//   UV  = source UV 0..1, origin top-left, y down (same as v_in.uv).
//   ISO = uv * float2(sf_aspect(), 1): 1 unit = source height. All distances/radii are ISO.
//   L/R = image left/right of an upright face. Angles in radians, positive = clockwise on screen.
//   Face frame ("local"): origin = midpoint of the eye sockets (corner midpoints, not the irises,
//   so it does not move with gaze), x = L->R eye, y = down the face, unit = socket distance.
//   Distances: length(sf_to_iso(a) - sf_to_iso(b)), never length(a - b) on UVs (ellipses at 16:9).
//   Face lost: values are stale or 0; gate with sf_face_ok(). Masks return "outside" by themselves.
//   meta.json must set "reset_on_face_lost": {"prompt": true, "default": true} (privacy effects:
//   "reset_on_face_lost": true, and fail closed), else fd_face_found never goes false.
//   Smooth fade in/out: see sf_presence_step().
#ifndef SILLY_FACE_HLSL
#define SILLY_FACE_HLSL

uniform bool      fd_face_found;
uniform float2    fd_bbox_tl;
uniform float2    fd_bbox_br;
uniform texture2d fd_points_tex;
uniform texture2d fd_preraster_tex;

sampler_state sf_point_sampler {
    Filter   = Point;
    AddressU = Clamp;
    AddressV = Clamp;
};

#define SF_NUM_LANDMARKS 478
#define SF_NUM_TRIANGLES 898

#define SF_LM_NOSE_TIP 1
#define SF_LM_CHIN 152
#define SF_LM_FOREHEAD 10
#define SF_LM_BETWEEN_EYES 168
#define SF_LM_CHEEK_L 234
#define SF_LM_CHEEK_R 454
#define SF_LM_IRIS_L 468
#define SF_LM_IRIS_R 473
#define SF_LM_EYE_L_OUTER 33
#define SF_LM_EYE_L_INNER 133
#define SF_LM_EYE_L_TOP 159
#define SF_LM_EYE_L_BOTTOM 145
#define SF_LM_EYE_R_INNER 362
#define SF_LM_EYE_R_OUTER 263
#define SF_LM_EYE_R_TOP 386
#define SF_LM_EYE_R_BOTTOM 374
#define SF_LM_MOUTH_L 61
#define SF_LM_MOUTH_R 291
#define SF_LM_LIP_IN_L 78
#define SF_LM_LIP_IN_R 308
#define SF_LM_LIP_IN_TOP 13
#define SF_LM_LIP_IN_BOTTOM 14
#define SF_LM_LIP_OUT_TOP 0
#define SF_LM_LIP_OUT_BOTTOM 17

#define SF_REGION_NONE 0
#define SF_REGION_FACE 1
#define SF_REGION_EYE_L 2
#define SF_REGION_EYE_R 3
#define SF_REGION_MOUTH 4

// ---- spaces ---------------------------------------------------------------------------------
float sf_aspect() { return vpixel / upixel; }
float2 sf_to_iso(float2 uv) { return uv * float2(vpixel / upixel, 1.0); }
float2 sf_from_iso(float2 iso) { return iso * float2(upixel / vpixel, 1.0); }
float2 sf_px(float2 uv) { return uv / float2(upixel, vpixel); }
float2 sf_rotate(float2 v, float a) {
    float c = cos(a);
    float s = sin(a);
    return float2(c * v.x - s * v.y, s * v.x + c * v.y);
}

// ---- landmarks (points texture: 478 x 4, rows sampled at their centres) ----------------------
float4 sf_points_row(float i, float row) {
    return fd_points_tex.Sample(sf_point_sampler, float2((i + 0.5) / 478.0, (row + 0.5) / 4.0));
}
float3 sf_lm3(int i) { return sf_points_row(float(i), 0.0).xyz; }
float2 sf_lm(int i) { return sf_points_row(float(i), 0.0).xy; }
float2 sf_lm_iso(int i) { return sf_to_iso(sf_lm(i)); }
float2 sf_canon(int i) { return sf_points_row(float(i), 3.0).xy; }
float sf_lm_dist(int a, int b) { return distance(sf_lm_iso(a), sf_lm_iso(b)); }

// ---- face scale, roll, validity (all from the eye sockets, stable under gaze) ----------------
float2 sf_eye_l_center() { return sf_lm(SF_LM_IRIS_L); }   // iris: pupils only
float2 sf_eye_r_center() { return sf_lm(SF_LM_IRIS_R); }
float2 sf_eye_l_socket() { return 0.5 * (sf_lm(SF_LM_EYE_L_OUTER) + sf_lm(SF_LM_EYE_L_INNER)); }
float2 sf_eye_r_socket() { return 0.5 * (sf_lm(SF_LM_EYE_R_OUTER) + sf_lm(SF_LM_EYE_R_INNER)); }
float2 sf_eyes_mid() { return 0.5 * (sf_eye_l_socket() + sf_eye_r_socket()); }
float sf_face_scale() { return distance(sf_to_iso(sf_eye_l_socket()), sf_to_iso(sf_eye_r_socket())); }
float sf_roll() {
    float2 d = sf_to_iso(sf_eye_r_socket()) - sf_to_iso(sf_eye_l_socket());
    return atan2(d.y, d.x);
}
bool sf_face_ok() {
    float s = sf_face_scale();
    return fd_face_found && s > 0.01 && s < 2.0;
}

// ---- face frame ------------------------------------------------------------------------------
float2 sf_face_x() {
    float2 d = sf_to_iso(sf_eye_r_socket()) - sf_to_iso(sf_eye_l_socket());
    return d / max(length(d), 1e-6);
}
float2 sf_face_y() {
    float2 x = sf_face_x();
    return float2(-x.y, x.x);
}
float2 sf_to_local(float2 uv) {
    float2 d = sf_to_iso(uv) - sf_to_iso(sf_eyes_mid());
    float s = max(sf_face_scale(), 1e-6);
    return float2(dot(d, sf_face_x()), dot(d, sf_face_y())) / s;
}
float2 sf_local_to_uv_dir(float2 local_dir) {
    float2 iso = (local_dir.x * sf_face_x() + local_dir.y * sf_face_y()) * sf_face_scale();
    return sf_from_iso(iso);
}
float2 sf_from_local(float2 local_pos) {
    return sf_eyes_mid() + sf_local_to_uv_dir(local_pos);
}

// ---- eyes ------------------------------------------------------------------------------------
float sf_eye_l_radius() { return 0.5 * sf_lm_dist(SF_LM_EYE_L_OUTER, SF_LM_EYE_L_INNER); }
float sf_eye_r_radius() { return 0.5 * sf_lm_dist(SF_LM_EYE_R_OUTER, SF_LM_EYE_R_INNER); }
float sf_iris_l_radius() { return 0.25 * (sf_lm_dist(470, 472) + sf_lm_dist(469, 471)); }
float sf_iris_r_radius() { return 0.25 * (sf_lm_dist(475, 477) + sf_lm_dist(474, 476)); }
float sf_eye_l_open() {
    return sf_lm_dist(SF_LM_EYE_L_TOP, SF_LM_EYE_L_BOTTOM) / max(sf_lm_dist(SF_LM_EYE_L_OUTER, SF_LM_EYE_L_INNER), 1e-6);
}
float sf_eye_r_open() {
    return sf_lm_dist(SF_LM_EYE_R_TOP, SF_LM_EYE_R_BOTTOM) / max(sf_lm_dist(SF_LM_EYE_R_OUTER, SF_LM_EYE_R_INNER), 1e-6);
}
// Normalized distance in an ellipse oriented along axis_iso (unit), 1 on the ellipse.
float sf_ellipse_dist(float2 uv, float2 center_uv, float2 axis_iso, float2 semi_iso) {
    float2 d = sf_to_iso(uv) - sf_to_iso(center_uv);
    float2 p = float2(dot(d, axis_iso), dot(d, float2(-axis_iso.y, axis_iso.x)));
    return length(p / max(semi_iso, float2(1e-6, 1e-6)));
}
float sf_eye_dist_impl(float2 uv, int outer_i, int inner_i, int top_i, int bottom_i) {
    float2 a = sf_lm_iso(outer_i);
    float2 b = sf_lm_iso(inner_i);
    float hw = 0.5 * distance(a, b);
    float2 axis = (b - a) / max(2.0 * hw, 1e-6);
    float hh = max(0.5 * sf_lm_dist(top_i, bottom_i), 0.25 * hw);
    return sf_ellipse_dist(uv, sf_from_iso(0.5 * (a + b)), axis, float2(hw, hh));
}
float sf_eye_l_dist(float2 uv) {
    return sf_eye_dist_impl(uv, SF_LM_EYE_L_OUTER, SF_LM_EYE_L_INNER, SF_LM_EYE_L_TOP, SF_LM_EYE_L_BOTTOM);
}
float sf_eye_r_dist(float2 uv) {
    return sf_eye_dist_impl(uv, SF_LM_EYE_R_INNER, SF_LM_EYE_R_OUTER, SF_LM_EYE_R_TOP, SF_LM_EYE_R_BOTTOM);
}

// ---- mouth, nose -----------------------------------------------------------------------------
float2 sf_mouth_center() {
    return 0.25 * (sf_lm(SF_LM_LIP_IN_TOP) + sf_lm(SF_LM_LIP_IN_BOTTOM) + sf_lm(SF_LM_LIP_IN_L) + sf_lm(SF_LM_LIP_IN_R));
}
float sf_mouth_gap() { return sf_lm_dist(SF_LM_LIP_IN_TOP, SF_LM_LIP_IN_BOTTOM); }
float sf_mouth_width() { return sf_lm_dist(SF_LM_MOUTH_L, SF_LM_MOUTH_R); }
float sf_mouth_open() {
    return clamp(sf_mouth_gap() / max(sf_lm_dist(SF_LM_LIP_IN_L, SF_LM_LIP_IN_R), 1e-6), 0.0, 2.0);
}
float sf_mouth_dist(float2 uv) {
    float2 a = sf_lm_iso(SF_LM_LIP_IN_L);
    float2 b = sf_lm_iso(SF_LM_LIP_IN_R);
    float hw = 0.5 * distance(a, b);
    float2 axis = (b - a) / max(2.0 * hw, 1e-6);
    float hh = max(0.5 * sf_mouth_gap(), 0.05 * hw);
    return sf_ellipse_dist(uv, sf_mouth_center(), axis, float2(hw, hh));
}
float2 sf_nose_tip() { return sf_lm(SF_LM_NOSE_TIP); }

// ---- bbox, ellipse, midline ------------------------------------------------------------------
// Face oval from fixed landmarks 10 (forehead), 152 (chin), 234/454 (cheeks), in the face frame.
// (fd_bbox_* is legacy: sf_face_bbox() only.)
float4 sf_face_bbox() { return float4(fd_bbox_tl, fd_bbox_br); }
float4 sf_face_oval_local() {   // (centre.xy, half_size.xy) in face-local units
    float2 t = sf_to_local(sf_lm(SF_LM_FOREHEAD));
    float2 b = sf_to_local(sf_lm(SF_LM_CHIN));
    float2 l = sf_to_local(sf_lm(SF_LM_CHEEK_L));
    float2 r = sf_to_local(sf_lm(SF_LM_CHEEK_R));
    float2 c = float2(0.5 * (l.x + r.x), 0.5 * (t.y + b.y));
    float2 h = max(float2(0.5 * abs(r.x - l.x), 0.5 * abs(b.y - t.y)), float2(1e-3, 1e-3));
    return float4(c, h);
}
float2 sf_face_center() { return sf_from_local(sf_face_oval_local().xy); }
float2 sf_face_half_size_iso() { return sf_face_oval_local().zw * sf_face_scale(); }   // along face x / y
float sf_face_ellipse_dist_rolled(float2 uv) {
    float4 o = sf_face_oval_local();
    return length((sf_to_local(uv) - o.xy) / o.zw);
}
float sf_face_ellipse_dist(float2 uv) {   // axis-aligned, same half sizes
    return sf_ellipse_dist(uv, sf_face_center(), float2(1.0, 0.0), sf_face_half_size_iso());
}
float sf_midline_side(float2 uv) {
    float2 a = sf_lm_iso(SF_LM_BETWEEN_EYES);
    float2 b = sf_lm_iso(SF_LM_CHIN);
    float2 dir = (b - a) / max(distance(a, b), 1e-6);
    float2 d = sf_to_iso(uv) - a;
    // dir points down the face; (dir.y, -dir.x) points to image-right for an upright face
    return dot(d, float2(dir.y, -dir.x));
}
float2 sf_mirror_midline(float2 uv) {
    float2 a = sf_lm_iso(SF_LM_BETWEEN_EYES);
    float2 b = sf_lm_iso(SF_LM_CHIN);
    float2 dir = (b - a) / max(distance(a, b), 1e-6);
    float2 d = sf_to_iso(uv) - a;
    float2 r = 2.0 * dot(d, dir) * dir - d;
    return sf_from_iso(a + r);
}

// ---- preraster masks -------------------------------------------------------------------------
float4 sf_preraster(float2 uv) { return fd_preraster_tex.Sample(sf_point_sampler, uv); }
int sf_tri_from_px(float4 px) {
    if (!sf_face_ok() || px.a < 0.5) {
        return -1;
    }
    return int(floor(px.r * 898.0));
}
int sf_tri_at(float2 uv) { return sf_tri_from_px(sf_preraster(uv)); }
float3 sf_bary_at(float2 uv) {
    float4 px = sf_preraster(uv);
    return float3(1.0 - px.g - px.b, px.g, px.b);
}
int3 sf_tri_vertices(int tri) {
    float t = float(tri);
    float row = 1.0;
    if (t >= 478.0) {
        row = 2.0;
        t -= 478.0;
    }
    float3 v = sf_points_row(t, row).xyz * 478.0;
    return int3(floor(v));
}
float2 sf_canon_at(float2 uv) {
    float4 px = sf_preraster(uv);
    int tri = sf_tri_from_px(px);
    if (tri < 0) {
        return float2(-1.0, -1.0);
    }
    int3 v = sf_tri_vertices(tri);
    float3 w = float3(1.0 - px.g - px.b, px.g, px.b);
    return w.x * sf_canon(v.x) + w.y * sf_canon(v.y) + w.z * sf_canon(v.z);
}
bool sf_tri_is_eye_l(float t) {
    return t == 38.0 || t == 39.0 || t == 406.0 || (t >= 427.0 && t <= 431.0) || (t >= 443.0 && t <= 447.0) || t == 449.0;
}
bool sf_tri_is_eye_r(float t) {
    return t == 506.0 || t == 509.0 || t == 821.0 || (t >= 842.0 && t <= 846.0) || (t >= 853.0 && t <= 857.0) || t == 859.0;
}
bool sf_tri_is_mouth(float t) {
    return t == 60.0 || t == 62.0 || t == 63.0 || t == 65.0 || t == 301.0 || t == 305.0 || t == 306.0
        || (t >= 308.0 && t <= 311.0) || t == 722.0 || (t >= 726.0 && t <= 728.0) || (t >= 730.0 && t <= 732.0);
}
int sf_region_at(float2 uv) {
    int tri = sf_tri_at(uv);
    if (tri < 0) {
        return SF_REGION_NONE;
    }
    float t = float(tri);
    if (sf_tri_is_eye_l(t)) {
        return SF_REGION_EYE_L;
    }
    if (sf_tri_is_eye_r(t)) {
        return SF_REGION_EYE_R;
    }
    if (sf_tri_is_mouth(t)) {
        return SF_REGION_MOUTH;
    }
    return SF_REGION_FACE;
}
bool sf_in_face(float2 uv) { return sf_tri_at(uv) >= 0; }
bool sf_in_eye_l(float2 uv) { return sf_region_at(uv) == SF_REGION_EYE_L; }
bool sf_in_eye_r(float2 uv) { return sf_region_at(uv) == SF_REGION_EYE_R; }
bool sf_in_eye(float2 uv) {
    int r = sf_region_at(uv);
    return r == SF_REGION_EYE_L || r == SF_REGION_EYE_R;
}
bool sf_in_mouth(float2 uv) { return sf_region_at(uv) == SF_REGION_MOUTH; }

// ---- warps -----------------------------------------------------------------------------------
// UV to sample for a bulge around center_uv: strength > 0 magnifies, < 0 pinches.
// Identity at and beyond radius_iso; smooth falloff.
float2 sf_bulge(float2 uv, float2 center_uv, float radius_iso, float strength) {
    float2 d = sf_to_iso(uv) - sf_to_iso(center_uv);
    float r = length(d) / max(radius_iso, 1e-6);
    if (r >= 1.0) {
        return uv;
    }
    float f = 1.0 - r * r;
    float k = 1.0 - strength * f * f;
    return sf_from_iso(sf_to_iso(center_uv) + d * k);
}
float2 sf_swirl(float2 uv, float2 center_uv, float radius_iso, float angle) {
    float2 d = sf_to_iso(uv) - sf_to_iso(center_uv);
    float r = length(d) / max(radius_iso, 1e-6);
    if (r >= 1.0) {
        return uv;
    }
    float f = 1.0 - r;
    return sf_from_iso(sf_to_iso(center_uv) + sf_rotate(d, angle * f * f));
}

// ---- presence fade ---------------------------------------------------------------------------
// Moves prev towards 1 (face found) or 0 (lost) at 1/fade_seconds per second. Keep it in a
// 1x1 "rgba16f" state pass so effects fade instead of popping on one-frame detection drops:
//   meta.json passes: [{"name":"presence","technique":"Presence","size":[1,1],"format":"rgba16f"}, {"name":"out"}]
//   uniform texture2d presence;  // own name = previous frame
//   float4 PSPresence(VertData v_in) : TARGET {
//       float p = presence.Sample(sf_point_sampler, v_in.uv).r;
//       return float4(sf_presence_step(p, 0.25), 0.0, 0.0, 1.0);
//   }
//   then in "out": float p = presence.Sample(sf_point_sampler, float2(0.5, 0.5)).r; ... lerp(src, fx, p)
float sf_presence_step(float prev, float fade_seconds) {
    float target = sf_face_ok() ? 1.0 : 0.0;
    float stepv = delta_time / max(fade_seconds, 1e-3);
    return clamp(prev + clamp(target - prev, -stepv, stepv), 0.0, 1.0);
}

#endif // SILLY_FACE_HLSL
