// Face Swap with Source (F8, PROVISIONAL D18): another OBS source worn as a face.
// Every face pixel gets its canonical face-model UV from the preraster triangle map (triangle id + barycentrics,
// sf_canon_at; the canonical UVs are MediaPipe's, shipped in the engine's points texture row 3). A per-axis affine
// maps the canonical eye sockets and mouth onto the eye/mouth positions the user set for the source.
@include "silly_face.hlsl"

uniform texture2d face_src;
uniform float2 face_src_size;   // (0,0) when no source is chosen -> passthrough
uniform float strength;
uniform bool  own_features;
uniform float edge;
uniform float shading;
uniform float src_cx;
uniform float src_eyes_y;
uniform float src_eye_dist;
uniform float src_mouth_y;
uniform texture2d presence;     // own name = previous frame's presence (1x1)
uniform texture2d shade;        // camera luma at 1/8 scale

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

float fw_luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

float4 PSPresence(VertData v_in) : TARGET {
    float p = presence.Sample(sf_point_sampler, v_in.uv).r;
    return float4(sf_presence_step(p, 0.25), 0.0, 0.0, 1.0);
}

// 1/8-scale camera luma (4 taps per output pixel so the downscale does not alias).
float4 PSShade(VertData v_in) : TARGET {
    float2 o = float2(upixel, vpixel) * 2.0;
    float l = fw_luma(image.Sample(textureSampler, v_in.uv + float2(-o.x, -o.y)).rgb)
            + fw_luma(image.Sample(textureSampler, v_in.uv + float2( o.x, -o.y)).rgb)
            + fw_luma(image.Sample(textureSampler, v_in.uv + float2(-o.x,  o.y)).rgb)
            + fw_luma(image.Sample(textureSampler, v_in.uv + float2( o.x,  o.y)).rgb);
    return float4(l * 0.25, 0.0, 0.0, 1.0);
}

// canonical UV (y up) -> image-style (y down)
float2 fw_canon_img(int i) {
    float2 c = sf_canon(i);
    return float2(c.x, 1.0 - c.y);
}

float4 PSDraw(VertData v_in) : TARGET {
    float4 src = image.Sample(textureSampler, v_in.uv);
    float p = presence.Sample(sf_point_sampler, float2(0.5, 0.5) + 0.0 * v_in.uv).r;
    if (p <= 0.001 || face_src_size.x < 0.5 || face_src_size.y < 0.5 || !sf_face_ok()) {
        return src;
    }
    float2 c = sf_canon_at(v_in.uv);
    if (c.x < 0.0) {
        return src;
    }
    float2 ci = float2(c.x, 1.0 - c.y);

    // canonical anchor points (image-style): eye sockets and inner-mouth centre
    float2 cl = 0.5 * (fw_canon_img(SF_LM_EYE_L_OUTER) + fw_canon_img(SF_LM_EYE_L_INNER));
    float2 cr = 0.5 * (fw_canon_img(SF_LM_EYE_R_OUTER) + fw_canon_img(SF_LM_EYE_R_INNER));
    float2 cm = 0.25 * (fw_canon_img(SF_LM_LIP_IN_TOP) + fw_canon_img(SF_LM_LIP_IN_BOTTOM)
                      + fw_canon_img(SF_LM_LIP_IN_L) + fw_canon_img(SF_LM_LIP_IN_R));
    float ce_y = 0.5 * (cl.y + cr.y);
    float ce_x = 0.5 * (cl.x + cr.x);
    float sx = src_eye_dist / max(cr.x - cl.x, 1e-4);
    float sy = (src_mouth_y - src_eyes_y) / max(cm.y - ce_y, 1e-4);
    float2 suv = float2(src_cx + (ci.x - ce_x) * sx, src_eyes_y + (ci.y - ce_y) * sy);
    float3 tex = face_src.Sample(textureSampler, suv).rgb;
    // outside the source image: fade instead of smearing its edge pixels
    float2 ins = smoothstep(float2(-0.02, -0.02), float2(0.02, 0.02), suv) * smoothstep(float2(-0.02, -0.02), float2(0.02, 0.02), 1.0 - suv);
    float w = ins.x * ins.y;

    // keep the user's light and shadow: local luma over the regional (face-sized) luma
    float fs = sf_face_scale();
    float2 r = sf_from_iso(float2(fs, fs));
    float lloc = shade.Sample(textureSampler, v_in.uv).r;
    float lreg = 0.2 * (shade.Sample(textureSampler, sf_face_center()).r
                      + shade.Sample(textureSampler, sf_face_center() + float2(r.x, 0.0)).r
                      + shade.Sample(textureSampler, sf_face_center() - float2(r.x, 0.0)).r
                      + shade.Sample(textureSampler, sf_face_center() + float2(0.0, r.y)).r
                      + shade.Sample(textureSampler, sf_face_center() - float2(0.0, r.y)).r);
    float lf = clamp(lloc / max(lreg, 0.02), 0.6, 1.4);
    tex = saturate(tex * lerp(1.0, lf, shading));

    // soft border towards the face outline (rolled oval through lm 10 / 152 / 234 / 454)
    float d = sf_face_ellipse_dist_rolled(v_in.uv);
    w *= 1.0 - smoothstep(1.0 - edge, 1.02, d);
    if (own_features) {
        w *= smoothstep(0.85, 1.35, sf_eye_l_dist(v_in.uv));
        w *= smoothstep(0.85, 1.35, sf_eye_r_dist(v_in.uv));
        w *= smoothstep(0.80, 1.25, sf_mouth_dist(v_in.uv));
    }
    return float4(lerp(src.rgb, tex, saturate(w * strength * p)), src.a);
}

technique Presence {
    pass {
        vertex_shader = VSDefault(v_in);
        pixel_shader  = PSPresence(v_in);
    }
}

technique Shade {
    pass {
        vertex_shader = VSDefault(v_in);
        pixel_shader  = PSShade(v_in);
    }
}

technique Draw {
    pass {
        vertex_shader = VSDefault(v_in);
        pixel_shader  = PSDraw(v_in);
    }
}
