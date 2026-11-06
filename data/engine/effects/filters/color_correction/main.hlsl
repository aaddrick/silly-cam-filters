// Color Correction. Port of OBS Studio's built-in Color Correction filter (color_filter, v2)
// by c3r1c3 and the OBS Project (GPL-2.0, plugins/obs-filters/color-correction-filter.c).
// Same settings names, ranges and math, so OBS color_filter settings carry over unchanged.
//
// OBS builds one 4x4 matrix on the CPU and applies it to a row vector:
//   pixel * Contrast * Brightness * Saturation * (Hue + Opacity) * (Multiply + Add)
// Here the same steps run one after another in the shader.

uniform float gamma;          // -3..3
uniform float contrast;       // -4..4
uniform float brightness;     // -1..1
uniform float saturation;     // -1..5
uniform float hue_shift;      // degrees
uniform float opacity;        // 0..1
uniform float4 color_multiply;
uniform float4 color_add;

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

float4 PSColorCorrection(VertData v_in) : TARGET
{
    // The engine passes straight (not premultiplied) alpha in and out, so the
    // un-premultiply / premultiply steps of OBS's shader are left out.
    float4 px = image.Sample(textureSampler, v_in.uv);

    // Gamma comes first.
    float g = (gamma < 0.0) ? (-gamma + 1.0) : (1.0 / (gamma + 1.0));
    px.rgb = pow(max(px.rgb, 0.0), float3(g, g, g));

    // Contrast: a plain scale (v2 does not pivot around 0.5).
    float c = (contrast < 0.0) ? (1.0 / (-contrast + 1.0)) : (contrast + 1.0);
    px.rgb *= c;

    // Brightness: matrix translation, so it is multiplied by the w (alpha) component.
    px.rgb += brightness * px.a;

    // Saturation with weights 0.299, 0.587, 0.114.
    float s = saturation + 1.0;
    float luma = dot(px.rgb, float3(0.299, 0.587, 0.114));
    px.rgb = luma * (1.0 - s) + px.rgb * s;

    // Hue: rotation around the grey axis (OBS's pseudo-quaternion matrix).
    float half_angle = 0.5 * radians(hue_shift);
    float k = 0.57735 * sin(half_angle);
    float kc = k * cos(half_angle);
    float d2 = 2.0 * (0.5 - 2.0 * k * k);
    float a2 = 2.0 * (k * k + kc);
    float b2 = 2.0 * (k * k - kc);
    px.rgb = float3(
        px.r * d2 + px.g * a2 + px.b * b2,
        px.r * b2 + px.g * d2 + px.b * a2,
        px.r * a2 + px.g * b2 + px.b * d2);
    px.a *= opacity;

    // Color multiply and color add (add is a translation, so it scales with alpha).
    px.rgb = px.rgb * color_multiply.rgb + color_add.rgb * px.a;

    return px;
}

technique Draw
{
    pass
    {
        vertex_shader = VSDefault(v_in);
        pixel_shader  = PSColorCorrection(v_in);
    }
}
