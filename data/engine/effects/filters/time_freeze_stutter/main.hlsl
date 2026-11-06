// Freeze Frame Stutter (Silly Cam Filters)
// Pass "hold": per-pixel state. rgb = frozen colour, a = seconds of freeze left (0 = not frozen).
//   Tiles are chosen by a hash of (tile id, frame), so all pixels of a tile freeze on the same frame.
//   Uses its own state (hold_prev), not the frame ring (D12).
// Pass "out": frozen pixels show the stored colour, others show the live source.

uniform float audio_level;      // dB, <= 0
uniform float audio_threshold;  // dB
uniform float tile_size;
uniform float freeze_time;
uniform float amount;

uniform texture2d hold_prev;
uniform texture2d hold;

sampler_state textureSampler {
    Filter    = Linear;
    AddressU  = Clamp;
    AddressV  = Clamp;
};
sampler_state pointSampler {
    Filter    = Point;
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

float hash21(float2 p)
{
    float3 p3 = frac(float3(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, float3(p3.y + 33.33, p3.z + 33.33, p3.x + 33.33));
    return frac((p3.x + p3.y) * p3.z);
}

float4 PSHold(VertData v_in) : TARGET
{
    float2 uv = v_in.uv;
    float4 src = image.Sample(textureSampler, uv);
    float4 st = hold_prev.Sample(pointSampler, uv);
    float dt = clamp(delta_time, 0.0, 0.1);

    // Still frozen: keep the stored colour, count down.
    if (st.a > dt) {
        return float4(st.rgb, st.a - dt);
    }

    // Not frozen. On a loud frame, a random tile may start a freeze.
    float2 px = float2(upixel, vpixel);
    float2 tile = floor(uv / (px * max(tile_size, 8.0)));
    float r = hash21(tile + float2(float(frame_index % 997) * 1.37, rand_seed * 91.0));
    bool loud = audio_level > audio_threshold;
    if (loud && r < amount) {
        return float4(src.rgb, max(freeze_time, 0.05));
    }
    return float4(src.rgb, 0.0);
}

float4 PSOut(VertData v_in) : TARGET
{
    float2 uv = v_in.uv;
    float4 src = image.Sample(textureSampler, uv);
    float4 h = hold.Sample(pointSampler, uv);
    if (h.a > 0.0) { return float4(h.rgb, src.a); }
    return src;
}

technique Hold { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSHold(v_in); } }
technique Draw { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSOut(v_in); } }
