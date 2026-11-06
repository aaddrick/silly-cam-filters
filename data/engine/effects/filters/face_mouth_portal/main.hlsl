// Mouth Portal (F7): another OBS source shown inside the open mouth (S1 inside-mouth mask x openness).
@include "silly_face.hlsl"

uniform texture2d portal;
uniform float2 portal_size;    // (0,0) when no source is chosen -> passthrough
uniform float min_open;
uniform float zoom;
uniform float rim;
uniform float4 rim_color;
uniform texture2d presence;    // own name = previous frame's presence (1x1)

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

float4 PSPresence(VertData v_in) : TARGET {
    float p = presence.Sample(sf_point_sampler, v_in.uv).r;
    return float4(sf_presence_step(p, 0.25), 0.0, 0.0, 1.0);
}

// Antialiased inside-mouth coverage: 4 rotated-grid taps of the preraster mouth mask (hard, 1 px).
float mp_mouth_cov(float2 uv) {
    float2 px = float2(upixel, vpixel);
    float c = 0.0;
    c += sf_in_mouth(uv + px * float2(-0.125, -0.375)) ? 0.25 : 0.0;
    c += sf_in_mouth(uv + px * float2( 0.375, -0.125)) ? 0.25 : 0.0;
    c += sf_in_mouth(uv + px * float2( 0.125,  0.375)) ? 0.25 : 0.0;
    c += sf_in_mouth(uv + px * float2(-0.375,  0.125)) ? 0.25 : 0.0;
    return c;
}

float4 PSDraw(VertData v_in) : TARGET {
    float4 src = image.Sample(textureSampler, v_in.uv);
    float p = presence.Sample(sf_point_sampler, float2(0.5, 0.5) + (v_in.uv - 0.5) * 1e-5).r;
    if (p <= 0.001 || portal_size.x < 0.5 || portal_size.y < 0.5 || !sf_face_ok()) {
        return src;
    }
    float open_amt = smoothstep(min_open, min_open + 0.08, sf_mouth_open());
    if (open_amt <= 0.0) {
        return src;
    }
    float cov = mp_mouth_cov(v_in.uv);
    if (cov <= 0.0) {
        return src;
    }

    // Map the source onto the mouth: centred on the mouth, rotated with the head, "cover"-fitted to the
    // opening (width = inner-lip width, grows only when the gap needs more height), zoom > 1 = closer.
    float2 a = sf_lm_iso(SF_LM_LIP_IN_L);
    float2 b = sf_lm_iso(SF_LM_LIP_IN_R);
    float hw = 0.5 * distance(a, b);
    float hh = 0.5 * sf_mouth_gap();
    float aspect = portal_size.x / portal_size.y;
    float wd = max(2.0 * hw * 1.15, 2.0 * hh * 1.15 * aspect) / max(zoom, 0.05);
    float2 d = sf_to_iso(v_in.uv) - sf_to_iso(sf_mouth_center());
    float2 l = sf_rotate(d, -sf_roll());
    float2 suv = float2(l.x / wd, l.y / (wd / aspect)) + 0.5;
    float3 inside = portal.Sample(textureSampler, suv).rgb;

    // Portal look: inner shadow at the lip edge, then a glow ring just inside the lips.
    float e = sf_mouth_dist(v_in.uv);                 // ~1 at the lip edge, 0 at the centre
    float shade = 1.0 - 0.45 * smoothstep(0.55, 1.05, e);
    float ring = smoothstep(0.6, 0.95, e) * rim;
    float pulse = 0.85 + 0.15 * sin(time * 4.0);
    float3 col = inside * shade;
    col = col + rim_color.rgb * ring * pulse * 0.9;

    float k = cov * open_amt * p;
    return float4(lerp(src.rgb, saturate(col), k), src.a);
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
