// Retro Effects: Frame Skip (ported from FiniteSingularity's obs-retro-effects, GPL-2.0)
// Shows a new source frame, then holds it for `skip_frames` frames.
// The held frame is this pass's own output from the previous frame (held_prev).

uniform int skip_frames;

uniform texture2d held_prev;

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

float4 PSFrameSkip(VertData v_in) : TARGET
{
    int period = max(skip_frames, 0) + 1;
    // frame_index starts at 0 and only grows, so the modulo is on positive values.
    bool new_frame = (frame_index % period) == 0;
    if (new_frame) {
        return image.Sample(textureSampler, v_in.uv);
    }
    return held_prev.Sample(textureSampler, v_in.uv);
}

technique Draw { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSFrameSkip(v_in); } }
