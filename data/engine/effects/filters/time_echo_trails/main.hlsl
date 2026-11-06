// Echo Trails (Silly Cam Filters)
// Pass "trail": a feedback buffer. Pixels that moved this frame are stored (hue-rotated);
// everything else fades out linearly and its hue keeps rotating. rgb = colour, a = strength.
// Pass "out": the source with the trail laid under/over it.

uniform float trail_length;
uniform float hue_speed;
uniform float motion_threshold;
uniform float strength;

uniform texture2d image_prev;
uniform texture2d trail_prev;
uniform texture2d trail;

sampler_state textureSampler {
    Filter    = Linear;
    AddressU  = Clamp;
    AddressV  = Clamp;
};

struct VertData {
    float4 pos : POSITION;
    float2 uv  : TEXCOORD0;
};

VertData VSDefault(VertData v_in)
{
    VertData vert_out;
    vert_out.pos = mul(float4(v_in.pos.xyz, 1.0), ViewProj);
    vert_out.uv  = v_in.uv;
    return vert_out;
}

// Rotate the hue of a colour by `turns` (1.0 = full circle), around the grey axis.
float3 hue_rotate(float3 c, float turns)
{
    float a = turns * 6.2831853;
    float cs = cos(a);
    float sn = sin(a);
    float3 k = float3(0.57735027, 0.57735027, 0.57735027);
    return c * cs + cross(k, c) * sn + k * dot(k, c) * (1.0 - cs);
}

float4 PSTrail(VertData v_in) : TARGET
{
    float2 uv = v_in.uv;
    float4 cur = image.Sample(textureSampler, uv);
    float4 old = image_prev.Sample(textureSampler, uv);
    float4 t = trail_prev.Sample(textureSampler, uv);

    // Existing trail: fade out linearly, rotate hue.
    float dt = clamp(delta_time, 0.0, 0.1);
    float fade = dt / max(trail_length, 0.05);
    float3 tc = hue_rotate(t.rgb, hue_speed * dt);
    float ta = max(t.a - fade, 0.0);

    // Motion this frame (max channel difference, so dark/bright changes both count).
    float3 d = abs(cur.rgb - old.rgb);
    float m = max(d.r, max(d.g, d.b));
    float mask = smoothstep(motion_threshold, motion_threshold * 2.0 + 0.001, m);

    // Echo colour: the moving pixel, pushed a little brighter and shifted in hue.
    float3 h = hue_rotate(cur.rgb, 0.33);
    float l = dot(h, float3(0.299, 0.587, 0.114));
    float3 echo = saturate(lerp(float3(l, l, l), h, 1.6) * 1.2);
    float3 nc = lerp(tc, echo, mask);
    float na = max(ta, mask);
    if (na < 0.001) { nc = float3(0.0, 0.0, 0.0); }
    return float4(nc, na);
}

float4 PSOut(VertData v_in) : TARGET
{
    float2 uv = v_in.uv;
    float4 src = image.Sample(textureSampler, uv);
    float4 t = trail.Sample(textureSampler, uv);
    float a = sqrt(t.a) * strength;
    float3 col = lerp(src.rgb, t.rgb, a);
    return float4(col, src.a);
}

technique Trail { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSTrail(v_in); } }
technique Draw  { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSOut(v_in); } }
