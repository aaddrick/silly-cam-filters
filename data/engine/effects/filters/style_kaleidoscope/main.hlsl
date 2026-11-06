// Kaleidoscope: polar fold. The plane around the centre is cut into `segments`
// slices; each slice shows the same wedge of the picture, mirrored about its middle,
// so the result is unchanged by a turn of 360/N degrees.

uniform int segments;
uniform float spin_speed;
uniform float zoom;
uniform float center_x;
uniform float center_y;

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

float2 mirror_wrap(float2 uv)
{
    float2 t = frac(uv * 0.5) * 2.0;
    return 1.0 - abs(1.0 - t);
}

float4 PSKaleido(VertData v_in) : TARGET
{
    float aspect = vpixel > 0.0 ? vpixel / upixel : 1.0;   // width / height
    float2 centre = float2(0.5 + center_x, 0.5 + center_y);
    float2 p = (v_in.uv - centre) * float2(aspect, 1.0);

    float r = length(p);
    float a = atan2(p.y, p.x);

    float seg = 6.283185 / float(segments);
    float spin = radians(spin_speed) * time;
    float f = fmod(a + 6.283185 * 4.0, seg);       // angle inside one slice
    if (f > seg * 0.5) f = seg - f;                 // mirror the second half: N-fold + mirror symmetry
    f += spin;

    float2 q = float2(cos(f), sin(f)) * r / zoom;
    float2 uv = centre + q / float2(aspect, 1.0);
    uv = mirror_wrap(uv);
    float4 c = image.Sample(textureSampler, uv);
    return float4(c.rgb, 1.0);
}

technique Draw { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSKaleido(v_in); } }
