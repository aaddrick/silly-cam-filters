// Face Stickers (F6): PNG stickers anchored on face landmarks, scaled by face size, rotated by head roll.
// Sticker art: gen_stickers.py in this folder (original, procedural). Anchors and widths below match it.
@include "silly_face.hlsl"

uniform int   sticker;
uniform texture2d img_nose;
uniform texture2d img_mustache;
uniform texture2d img_glasses;
uniform texture2d custom_image;
uniform float2 img_nose_size;
uniform float2 img_mustache_size;
uniform float2 img_glasses_size;
uniform float2 custom_image_size;
uniform int   custom_anchor;
uniform float custom_width;
uniform float size;
uniform float offset_x;
uniform float offset_y;
uniform texture2d presence;   // own name = previous frame's presence (1x1)

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

// Sticker widths in face units (1 = eye-socket distance), from the PNG geometry (gen_stickers.py).
#define FS_W_NOSE     0.70    // ball = 0.90 of the image -> ~0.63 eye distances
#define FS_W_GLASSES  2.2262  // lens centres 0.4492 of the width apart -> exactly on the eye sockets
#define FS_W_MUSTACHE 1.60

// Face scale that does not shrink when the head turns sideways (S1 addendum, measured constant 0.371).
float fs_scale() {
    return max(sf_face_scale(), 0.371 * sf_lm_dist(SF_LM_FOREHEAD, SF_LM_CHIN));
}

// Sticker-space UV of a pixel: anchor at the image centre, width w_iso, height = w_iso * aspect.
// Returns the uv and, in .zw, the size of one output pixel in sticker uv (for footprint taps).
float4 fs_sticker_uv(float2 uv, float2 anchor_uv, float w_iso, float aspect, float roll) {
    float2 d = sf_to_iso(uv) - sf_to_iso(anchor_uv);
    float2 l = sf_rotate(d, -roll);
    float h_iso = w_iso * aspect;
    return float4(l.x / w_iso + 0.5, l.y / h_iso + 0.5, vpixel / w_iso, vpixel / h_iso);
}

bool fs_inside(float2 suv, float2 pad) {
    return suv.x > -pad.x && suv.x < 1.0 + pad.x && suv.y > -pad.y && suv.y < 1.0 + pad.y;
}

// 3x3 footprint taps along the sticker axes (the PNGs are big and have no mipmaps): straight alpha,
// colour bled into the transparent area by the generator, so a linear tap never pulls in black.
// Result is premultiplied (rgb * a, a).
float4 fs_tap_nose(float4 st) {
    float4 acc = float4(0.0, 0.0, 0.0, 0.0);
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            float4 c = img_nose.Sample(textureSampler, st.xy + float2(float(i), float(j)) * st.zw * 0.333);
            acc += float4(c.rgb * c.a, c.a);
        }
    }
    return acc / 9.0;
}
float4 fs_tap_mustache(float4 st) {
    float4 acc = float4(0.0, 0.0, 0.0, 0.0);
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            float4 c = img_mustache.Sample(textureSampler, st.xy + float2(float(i), float(j)) * st.zw * 0.333);
            acc += float4(c.rgb * c.a, c.a);
        }
    }
    return acc / 9.0;
}
float4 fs_tap_glasses(float4 st) {
    float4 acc = float4(0.0, 0.0, 0.0, 0.0);
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            float4 c = img_glasses.Sample(textureSampler, st.xy + float2(float(i), float(j)) * st.zw * 0.333);
            acc += float4(c.rgb * c.a, c.a);
        }
    }
    return acc / 9.0;
}

// User PNGs may store black (or anything) under alpha 0: premultiply each texel before filtering
// (manual bilinear on point fetches), so edges never get a dark fringe.
float4 fs_texel_custom(float2 p) {
    float4 c = custom_image.Sample(sf_point_sampler, (p + 0.5) / custom_image_size);
    float inside = (p.x >= 0.0 && p.y >= 0.0 && p.x < custom_image_size.x && p.y < custom_image_size.y) ? 1.0 : 0.0;
    return float4(c.rgb * c.a, c.a) * inside;
}
float4 fs_bilinear_custom(float2 suv) {
    float2 p = suv * custom_image_size - 0.5;
    float2 f = frac(p);
    float2 b = floor(p);
    float4 a00 = fs_texel_custom(b);
    float4 a10 = fs_texel_custom(b + float2(1.0, 0.0));
    float4 a01 = fs_texel_custom(b + float2(0.0, 1.0));
    float4 a11 = fs_texel_custom(b + float2(1.0, 1.0));
    return lerp(lerp(a00, a10, f.x), lerp(a01, a11, f.x), f.y);
}
float4 fs_tap_custom(float4 st) {
    float4 acc = float4(0.0, 0.0, 0.0, 0.0);
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            acc += fs_bilinear_custom(st.xy + float2(float(i), float(j)) * st.zw * 0.333);
        }
    }
    return acc / 9.0;
}

float3 fs_over(float3 dst, float4 premul) {
    return dst * (1.0 - premul.a) + premul.rgb;
}

float4 PSPresence(VertData v_in) : TARGET {
    float p = presence.Sample(sf_point_sampler, v_in.uv).r;
    return float4(sf_presence_step(p, 0.3), 0.0, 0.0, 1.0);
}

float4 PSDraw(VertData v_in) : TARGET {
    float4 src = image.Sample(textureSampler, v_in.uv);
    float p = presence.Sample(sf_point_sampler, float2(0.5, 0.5) + 0.0 * v_in.uv).r;
    float s = fs_scale();
    // Stale landmarks are kept bound after a loss, so the sticker fades out in place.
    // Before the first detection the points texture is empty (scale 0): draw nothing.
    if (p <= 0.001 || !(s > 0.01 && s < 2.0)) {
        return src;
    }
    float roll = sf_roll();
    float2 off = sf_local_to_uv_dir(float2(offset_x, offset_y));
    float k = sf_face_scale() > 0.0 ? s / sf_face_scale() : 1.0;   // robust scale / socket scale
    float unit = s * size;                                         // ISO width of one face unit
    float3 c = src.rgb;
    float2 pad = float2(0.02, 0.02);

    bool all3 = sticker == 3;
    if (sticker == 1 || all3) {
        float2 a = lerp(sf_lm(2), sf_lm(SF_LM_LIP_OUT_TOP), 0.3) + off;
        float asp = img_mustache_size.x > 0.0 ? img_mustache_size.y / img_mustache_size.x : 0.390625;
        float4 st = fs_sticker_uv(v_in.uv, a, FS_W_MUSTACHE * unit, asp, roll);
        if (fs_inside(st.xy, pad)) {
            c = fs_over(c, fs_tap_mustache(st));
        }
    }
    if (sticker == 2 || all3) {
        // the glasses' lens distance must match the sockets, so they use the socket scale times size
        float2 a = sf_eyes_mid() + off;
        float asp = img_glasses_size.x > 0.0 ? img_glasses_size.y / img_glasses_size.x : 0.41015625;
        float4 st = fs_sticker_uv(v_in.uv, a, FS_W_GLASSES * unit / k, asp, roll);
        if (fs_inside(st.xy, pad)) {
            c = fs_over(c, fs_tap_glasses(st));
        }
    }
    if (sticker == 0 || all3) {
        float2 a = sf_nose_tip() + off;
        float asp = img_nose_size.x > 0.0 ? img_nose_size.y / img_nose_size.x : 1.0;
        float4 st = fs_sticker_uv(v_in.uv, a, FS_W_NOSE * unit, asp, roll);
        if (fs_inside(st.xy, pad)) {
            c = fs_over(c, fs_tap_nose(st));
        }
    }
    if (sticker == 4 && custom_image_size.x > 0.5 && custom_image_size.y > 0.5) {
        float2 a = sf_nose_tip();
        if (custom_anchor == 1) {
            a = lerp(sf_lm(2), sf_lm(SF_LM_LIP_OUT_TOP), 0.3);
        } else if (custom_anchor == 2) {
            a = sf_eyes_mid();
        } else if (custom_anchor == 3) {
            a = lerp(sf_eyes_mid(), sf_lm(SF_LM_FOREHEAD), 0.6);
        } else if (custom_anchor == 4) {
            a = sf_lm(SF_LM_CHIN);
        }
        float asp = custom_image_size.y / custom_image_size.x;
        float4 st = fs_sticker_uv(v_in.uv, a + off, custom_width * unit, asp, roll);
        if (fs_inside(st.xy, pad)) {
            c = fs_over(c, fs_tap_custom(st));
        }
    }
    return float4(lerp(src.rgb, c, p), src.a);
}

technique Presence {
    pass {
        vertex_shader = VSDefault(v_in);
        pixel_shader  = PSPresence(v_in);
    }
}

technique Draw {
    pass {
        vertex_shader = VSDefault(v_in);
        pixel_shader  = PSDraw(v_in);
    }
}
