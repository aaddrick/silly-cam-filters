// Face Censor: pixelate or blur the face. FAILS CLOSED (D17): with no valid face (before the first detection,
// face lost, garbage landmarks) the whole frame is censored. The mask is the face oval (landmarks 10/152/234/454,
// in the face frame, so it rolls with the head) dilated by "margin" plus a speed term (the landmarks lag a moving
// face), united with the face mesh itself (preraster), with a soft edge that lies entirely OUTSIDE that area.
// track (1x1 rgba32f): (eyes-mid.xy UV, smoothed speed ISO/s, last block size ISO)
@include "silly_face.hlsl"

uniform int style;
uniform float block;
uniform float margin;
uniform texture2d track;
uniform texture2d track_prev;
uniform texture2d blurh;
uniform texture2d blurv;

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

#define FC_LATENCY 0.2          // seconds of landmark lag the speed margin covers
#define FC_FALLBACK_BLOCK 0.05  // block size (ISO) when no face is known: ~1/20 of the frame height

// block size in ISO units: a fraction of the face width (~2.2 socket distances)
float fc_block_iso(float last) {
    if (sf_face_ok()) {
        return max(block * 2.2 * sf_face_scale(), 3.0 * vpixel);
    }
    return (last > 0.0) ? max(last, FC_FALLBACK_BLOCK) : FC_FALLBACK_BLOCK;
}

float4 PSTrack(VertData v_in) : TARGET {
    float4 prev = track_prev.Sample(sf_point_sampler, v_in.uv);
    float dt = clamp(delta_time, 0.001, 0.1);
    if (!sf_face_ok()) {
        return float4(prev.xy, 0.0, prev.w);
    }
    float2 mid = sf_eyes_mid();
    bool fresh = prev.z <= 0.0 && prev.x == 0.0 && prev.y == 0.0;
    float spd = fresh ? 0.0 : distance(sf_to_iso(mid), sf_to_iso(prev.xy)) / dt;
    // rise fast, fall slowly (~0.3 s), so the margin is already wide when the face starts moving again
    float s = (spd > prev.z) ? spd : lerp(prev.z, spd, 1.0 - exp(-dt / 0.3));
    return float4(mid, max(s, 1e-6), fc_block_iso(prev.w));
}

// --- blur (quarter scale, separable, 9 taps, spacing from the block size). Two copies, because OBS's GLSL
// translation does not accept texture2d function parameters.
float2 blur_step(float2 dir) {
    float4 t = track.Sample(sf_point_sampler, float2(0.5, 0.5));
    return sf_from_iso(dir * fc_block_iso(t.w) * 0.25);
}
float4 PSBlurH(VertData v_in) : TARGET {
    float2 stepv = blur_step(float2(1.0, 0.0));
    float4 acc = float4(0.0, 0.0, 0.0, 0.0);
    float wsum = 0.0;
    for (int i = -4; i <= 4; i++) {
        float w = exp(-0.5 * float(i * i) / 6.0);
        acc += w * image.Sample(textureSampler, v_in.uv + stepv * float(i));
        wsum += w;
    }
    return acc / wsum;
}
float4 PSBlurV(VertData v_in) : TARGET {
    float2 stepv = blur_step(float2(0.0, 1.0));
    float4 acc = float4(0.0, 0.0, 0.0, 0.0);
    float wsum = 0.0;
    for (int i = -4; i <= 4; i++) {
        float w = exp(-0.5 * float(i * i) / 6.0);
        acc += w * blurh.Sample(textureSampler, v_in.uv + stepv * float(i));
        wsum += w;
    }
    return acc / wsum;
}

float4 pixelate(float2 uv, float b) {
    float2 iso = sf_to_iso(uv);
    float2 cell = floor(iso / b);
    float4 acc = float4(0.0, 0.0, 0.0, 0.0);
    for (int j = 0; j < 4; j++) {
        for (int i = 0; i < 4; i++) {
            float2 q = (cell + (float2(float(i), float(j)) + 0.5) / 4.0) * b;
            acc += image.Sample(textureSampler, sf_from_iso(q));
        }
    }
    return acc / 16.0;
}

float4 censored(float2 uv, float b) {
    if (style == 1) {
        return blurv.Sample(textureSampler, uv);
    }
    return pixelate(uv, b);
}

float4 PSDraw(VertData v_in) : TARGET {
    float4 src = image.Sample(textureSampler, v_in.uv);
    float4 t = track.Sample(sf_point_sampler, float2(0.5, 0.5));
    float b = fc_block_iso(t.w);
    if (!sf_face_ok()) {
        return float4(censored(v_in.uv, b).rgb, src.a);   // fail closed
    }
    float s = max(sf_face_scale(), 1e-4);
    float4 o = sf_face_oval_local();
    // dilation in face-local units: margin x oval size, plus speed x latency, plus one block (pixel blocks
    // straddling the edge must still be censored)
    float2 grow = o.zw * margin + (t.z * FC_LATENCY + b) / s;
    float d = length((sf_to_local(v_in.uv) - o.xy) / (o.zw + grow));
    float w = 1.0 - smoothstep(1.0, 1.08, d);        // soft edge only outside the dilated oval
    if (sf_in_face(v_in.uv)) {
        w = 1.0;
    }
    if (w <= 0.0) {
        return src;
    }
    return float4(lerp(src.rgb, censored(v_in.uv, b).rgb, w), src.a);
}

technique Track { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSTrack(v_in); } }
technique BlurH { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSBlurH(v_in); } }
technique BlurV { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSBlurV(v_in); } }
technique Draw  { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSDraw(v_in); } }
