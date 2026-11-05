/*
 * The obs-shaderfilter effect template, copied from obs-shaderfilter 2.6.0
 * (https://github.com/exeldro/obs-shaderfilter, GPL-2.0) by Exeldro,
 * Charles Fettinger and nleseul.
 *
 * The engine wraps .shader files in this template, as obs-shaderfilter does.
 */
#pragma once

static const char *const sf_effect_template_begin = "\
uniform float4x4 ViewProj;\n\
uniform texture2d image;\n\
\n\
uniform float2 uv_offset;\n\
uniform float2 uv_scale;\n\
uniform float2 uv_pixel_interval;\n\
uniform float2 uv_size;\n\
uniform float rand_f;\n\
uniform float rand_instance_f;\n\
uniform float rand_activation_f;\n\
uniform float elapsed_time;\n\
uniform float elapsed_time_start;\n\
uniform float elapsed_time_show;\n\
uniform float elapsed_time_active;\n\
uniform float elapsed_time_enable;\n\
uniform int loops;\n\
uniform float loop_second;\n\
uniform float local_time;\n\
\n\
sampler_state textureSampler{\n\
	Filter = Linear;\n\
	AddressU = Border;\n\
	AddressV = Border;\n\
	BorderColor = 00000000;\n\
};\n\
\n\
struct VertData {\n\
	float4 pos : POSITION;\n\
	float2 uv : TEXCOORD0;\n\
};\n\
\n\
VertData mainTransform(VertData v_in)\n\
{\n\
	VertData vert_out;\n\
	vert_out.pos = mul(float4(v_in.pos.xyz, 1.0), ViewProj);\n\
	vert_out.uv = v_in.uv * uv_scale + uv_offset;\n\
	return vert_out;\n\
}\n\
\n\
float srgb_nonlinear_to_linear_channel(float u)\n\
{\n\
	return (u <= 0.04045) ? (u / 12.92) : pow((u + 0.055) / 1.055, 2.4);\n\
}\n\
\n\
float3 srgb_nonlinear_to_linear(float3 v)\n\
{\n\
	return float3(srgb_nonlinear_to_linear_channel(v.r),\n\
		      srgb_nonlinear_to_linear_channel(v.g),\n\
		      srgb_nonlinear_to_linear_channel(v.b));\n\
}\n\
\n";

static const char *const sf_effect_template_default_image_shader = "\n\
float4 mainImage(VertData v_in) : TARGET\n\
{\n\
	return image.Sample(textureSampler, v_in.uv);\n\
}\n\
";

static const char *const sf_effect_template_default_transition_image_shader = "\n\
uniform texture2d image_a;\n\
uniform texture2d image_b;\n\
uniform float transition_time = 0.5;\n\
uniform bool convert_linear = true;\n\
\n\
float4 mainImage(VertData v_in) : TARGET\n\
{\n\
	float4 a_val = image_a.Sample(textureSampler, v_in.uv);\n\
	float4 b_val = image_b.Sample(textureSampler, v_in.uv);\n\
	float4 rgba = lerp(a_val, b_val, transition_time);\n\
	if (convert_linear)\n\
		rgba.rgb = srgb_nonlinear_to_linear(rgba.rgb);\n\
	return rgba;\n\
}\n\
";

static const char *const sf_effect_template_end = "\n\
technique Draw\n\
{\n\
	pass\n\
	{\n\
		vertex_shader = mainTransform(v_in);\n\
		pixel_shader = mainImage(v_in);\n\
	}\n\
}\n";

