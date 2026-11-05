// Retro Effects: Posterize (ported from FiniteSingularity's obs-retro-effects, GPL-2.0)
// 0: round each channel to `levels` steps
// 1: round the luminance, then map it from Color 1 to Color 2
// 2: round the luminance, then look the color up across the middle row of another source

uniform int    posterize_levels;
uniform int    posterize_technique;
uniform float4 posterize_color_1;
uniform float4 posterize_color_2;
uniform texture2d posterize_map_source;
uniform float2 posterize_map_source_size; // (-1, -1) when no source is chosen

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

float4 PSPosterize(VertData v_in) : TARGET
{
    float4 color = image.Sample(textureSampler, v_in.uv);
    float levels = max(float(posterize_levels) - 1.0, 1.0);

    if (posterize_technique == 1) {
        float lum = color.r * 0.299 + color.g * 0.587 + color.b * 0.114;
        lum = round(lum * levels) / levels;
        float4 c = lerp(posterize_color_1, posterize_color_2, float4(lum, lum, lum, lum));
        c.a *= color.a;
        return c;
    }
    if (posterize_technique == 2) {
        // Like the C filter: without a map source, pass the image through.
        if (posterize_map_source_size.x <= 0.0) {
            return color;
        }
        float lum = color.r * 0.299 + color.g * 0.587 + color.b * 0.114;
        lum = round(lum * levels) / levels;
        float4 c = posterize_map_source.Sample(textureSampler, float2(lum, 0.5));
        c.a *= color.a;
        return c;
    }

    color.rgb = round(color.rgb * levels) / levels;
    return color;
}

technique Draw { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSPosterize(v_in); } }
