// Echo Trails (Silly Cam Filters)
// Pass "stamp": per-pixel memory of what moved. rgb = the true colour of the thing that moved
//   (kept when it leaves, so the trail is the object, not the background it uncovers),
//   a = freshness (1 -> 0 over trail_length seconds).
// Pass "out": the live source on top; where a fresh stamp no longer matches the live pixel
//   (the object has gone), a bright hue-cycling echo of the stamp is drawn. Moving live pixels stay natural.

uniform float trail_length;
uniform float hue_speed;
uniform float motion_threshold;
uniform float strength;

uniform texture2d image_prev;
uniform texture2d stamp_prev;
uniform texture2d stamp;

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

float maxabs(float3 v) { return max(abs(v.r), max(abs(v.g), abs(v.b))); }

float4 PSStamp(VertData v_in) : TARGET
{
    float2 uv = v_in.uv;
    float3 cur = image.Sample(textureSampler, uv).rgb;
    float3 old = image_prev.Sample(textureSampler, uv).rgb;
    float4 t = stamp_prev.Sample(textureSampler, uv);

    float dt = clamp(delta_time, 0.0, 0.1);
    float fresh = max(t.a - dt / max(trail_length, 0.05), 0.0);

    float m = maxabs(cur - old);
    float mask = smoothstep(motion_threshold, motion_threshold * 2.0 + 0.001, m);
    if (mask < 0.5) {
        return float4(t.rgb, fresh);
    }
    // Moving pixel. If what was there before is what we stamped, the object is leaving: keep the stamp.
    // Otherwise something new arrived: stamp it.
    bool leaving = (t.a > 0.05) && (maxabs(old - t.rgb) < 0.12);
    float3 rgb = leaving ? t.rgb : cur;
    return float4(rgb, max(fresh, mask));
}

float4 PSOut(VertData v_in) : TARGET
{
    float2 uv = v_in.uv;
    float4 src = image.Sample(textureSampler, uv);
    float4 st = stamp.Sample(textureSampler, uv);

    // Live object (matches its stamp) stays untouched.
    float differs = smoothstep(0.05, 0.2, maxabs(src.rgb - st.rgb));
    // Pixels moving right now are the live picture: keep them mostly natural.
    float dm = maxabs(src.rgb - image_prev.Sample(textureSampler, uv).rgb);
    float live = smoothstep(motion_threshold, motion_threshold * 2.0 + 0.001, dm);

    // Echo colour: saturated, bright, hue shifts with the age of the trail.
    float age = (1.0 - st.a) * trail_length;
    float3 h = hue_rotate(st.rgb, 0.33 + hue_speed * age);
    float mx = max(h.r, max(h.g, h.b));
    float3 n = h / max(mx, 0.05);
    n = lerp(float3(1.0, 1.0, 1.0), n, 0.75);
    float3 echo = saturate(n * max(mx, 0.65));

    float a = sqrt(st.a) * strength * differs * lerp(1.0, 0.15, live);
    return float4(lerp(src.rgb, echo, a), src.a);
}

technique Stamp { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSStamp(v_in); } }
technique Draw  { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSOut(v_in); } }
