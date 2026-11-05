// Retro Effects: Scanlines (ported from FiniteSingularity's obs-retro-effects, GPL-2.0)
// Darkens the image with a periodic line pattern that scrolls at `speed` px/s.
// The C filter accumulates the scroll offset on the CPU; here it is time * speed.

#define TAU 6.2831855

uniform int   scanlines_profile;
uniform float scanlines_period;
uniform float scanlines_speed;
uniform float scanlines_intensity;

uniform float2 uv_size;

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

// C/HLSL fmod: the result has the sign of x. Written out so the GLSL build behaves the same.
float c_fmod(float x, float y)
{
    float q = x / y;
    return x - y * (sign(q) * floor(abs(q)));
}

float4 PSScanlines(VertData v_in) : TARGET
{
    float period = max(scanlines_period, 0.001);
    float intensity = scanlines_intensity / 100.0;
    float offset = c_fmod(time * scanlines_speed, period);

    float2 coord = v_in.uv * uv_size;
    float4 color = image.Sample(textureSampler, v_in.uv);
    float coord_y = c_fmod(coord.y - offset, period);
    float a = abs(coord_y);

    float step_val;
    if (scanlines_profile == 1) {
        // Square
        step_val = step(0.25 * period, a) * (1.0 - step(0.75 * period, a));
    } else if (scanlines_profile == 2) {
        // Saw-tooth (the C filter drew a sine here; see the port notes)
        step_val = a / period;
    } else if (scanlines_profile == 3) {
        // Smooth step
        step_val = smoothstep(0.0, 0.333 * period, a) * (1.0 - smoothstep(0.667 * period, period, a));
    } else if (scanlines_profile == 4) {
        // Triangular
        step_val = 2.0 * abs(a / period - 0.5);
    } else {
        // Sin wave
        step_val = (1.0 + sin(TAU * (coord.y - offset) / period)) / 2.0;
    }

    float v = 1.0 - intensity + intensity * step_val;
    return float4(color.rgb * v, color.a);
}

technique Draw { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSScanlines(v_in); } }
