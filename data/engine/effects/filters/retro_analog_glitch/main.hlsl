// Retro: Analog Glitch
// Port of the Analog Glitch filter from obs-retro-effects 1.0.2 by FiniteSingularity
// (itself based on ShaderToy "Video Glitch" by dyvoid, https://www.shadertoy.com/view/XtK3W3).
// GPL-2.0, as the original.
//
// Differences from the original: the uint PCG hashes are replaced by float hashes
// (OBS's HLSL->GLSL translation and older GL drivers do not handle the uint code well),
// so the noise has the same character but not the same exact values.

uniform float analog_glitch_max_disp;
uniform float analog_glitch_primary_speed;
uniform float analog_glitch_primary_scale;
uniform float analog_glitch_primary_threshold;
uniform float analog_glitch_secondary_speed;
uniform float analog_glitch_secondary_scale;
uniform float analog_glitch_secondary_threshold;
uniform float analog_glitch_secondary_influence;
uniform float analog_glitch_interference_magnitude;
uniform float analog_glitch_line_magnitude;
uniform bool analog_glitch_interfence_alpha;
uniform float analog_glitch_ca_max_disp;
uniform float analog_glitch_desat_amount;

uniform float elapsed_time;
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

// ---------------------------------------------------------------------------
// Noise helpers (float only)

float pmod(float x, float y)
{
    return x - y * floor(x / y);
}

float3 pmod3(float3 x, float y)
{
    return x - y * floor(x / y);
}

// Dave Hoskins' "hash without sine", 3 in -> 1 out, [0, 1)
float hash13(float3 p3)
{
    p3 = frac(p3 * 0.1031);
    p3 += dot(p3, p3.zyx + 31.32);
    return frac((p3.x + p3.y) * p3.z);
}


// K.jpg's OpenSimplex2S (smooth, 8-point BCC), value only.
float3 os_grad(float hash)
{
    float3 cube = pmod3(floor(hash / float3(1.0, 2.0, 4.0)), 2.0) * 2.0 - 1.0;
    float3 cuboct = cube;
    float index = floor(hash / 16.0);
    if (index < 0.5)
        cuboct.x = 0.0;
    else if (index < 1.5)
        cuboct.y = 0.0;
    else
        cuboct.z = 0.0;
    float type = pmod(floor(hash / 8.0), 2.0);
    float3 rhomb = (1.0 - type) * cube + type * (cuboct + cross(cube, cuboct));
    float3 g = cuboct * 1.22474487139 + rhomb;
    g *= (1.0 - 0.042942436724648037 * type) * 3.5946317686139184;
    return g;
}

float os_part(float3 X)
{
    float3 b = floor(X);
    float4 i4 = float4(X - b, 2.5);

    float3 v1 = b + floor(dot(i4, float4(0.25, 0.25, 0.25, 0.25)));
    float3 v2 = b + float3(1.0, 0.0, 0.0) + float3(-1.0, 1.0, 1.0) * floor(dot(i4, float4(-0.25, 0.25, 0.25, 0.35)));
    float3 v3 = b + float3(0.0, 1.0, 0.0) + float3(1.0, -1.0, 1.0) * floor(dot(i4, float4(0.25, -0.25, 0.25, 0.35)));
    float3 v4 = b + float3(0.0, 0.0, 1.0) + float3(1.0, 1.0, -1.0) * floor(dot(i4, float4(0.25, 0.25, -0.25, 0.35)));

    float4 hashes = float4(hash13(v1), hash13(v2), hash13(v3), hash13(v4)) * 47.0;

    float3 d1 = X - v1;
    float3 d2 = X - v2;
    float3 d3 = X - v3;
    float3 d4 = X - v4;
    float4 a = max(float4(0.75, 0.75, 0.75, 0.75) - float4(dot(d1, d1), dot(d2, d2), dot(d3, d3), dot(d4, d4)), float4(0.0, 0.0, 0.0, 0.0));
    float4 aa = a * a;
    float4 aaaa = aa * aa;
    float4 extrapolations = float4(dot(d1, os_grad(hashes.x)), dot(d2, os_grad(hashes.y)),
                                   dot(d3, os_grad(hashes.z)), dot(d4, os_grad(hashes.w)));
    return dot(aaaa, extrapolations);
}

float open_simplex_1d(float2 coord, float t, float2 scale)
{
    coord *= 1.0 / scale;
    float3 X = float3(coord, t);
    // "Conventional" orientation
    X = dot(X, float3(2.0 / 3.0, 2.0 / 3.0, 2.0 / 3.0)) - X;
    return os_part(X) + os_part(X + 144.5);
}

// ---------------------------------------------------------------------------

float4 sampleDesaturatedTexture(float2 xy, float desat)
{
    float4 col = image.Sample(textureSampler, xy / uv_size);
    float lum = dot(col.rgb, float3(0.299, 0.587, 0.114));
    col.rgb = lerp(col.rgb, float3(lum, lum, lum), float3(desat, desat, desat));
    return col;
}

float4 PSAnalogGlitch(VertData v_in) : TARGET
{
    float t = elapsed_time;
    float2 coord = v_in.uv * uv_size;

    float n_primary = open_simplex_1d(float2(t * analog_glitch_primary_speed, coord.y), 0.0,
                                      float2(1.0, max(analog_glitch_primary_scale, 0.0001)));
    float n_secondary = open_simplex_1d(float2(t * analog_glitch_secondary_speed, coord.y), 0.0,
                                        float2(1.0, max(analog_glitch_secondary_scale, 0.0001)));

    // (The original never uses the secondary threshold in the shader.)
    n_primary = max(0.0, (n_primary - analog_glitch_primary_threshold)) / max(1.0 - analog_glitch_primary_threshold, 0.0001);
    n_primary += n_secondary * analog_glitch_secondary_influence;
    n_primary /= (1.0 + analog_glitch_secondary_influence);

    coord.x = coord.x - analog_glitch_max_disp * n_primary * n_primary;

    // Color drift and desaturation
    float desat = n_primary * analog_glitch_desat_amount / 100.0;
    float drift = n_primary * analog_glitch_ca_max_disp;
    float4 col_g = sampleDesaturatedTexture(coord, desat);
    float4 col_r = sampleDesaturatedTexture(coord - float2(drift, 0.0), desat);
    float4 col_b = sampleDesaturatedTexture(coord + float2(drift, 0.0), desat);

    float4 col = float4(col_r.r, col_g.g, col_b.b, (col_r.a + col_g.a + col_b.a) * 0.33334);

    // Interference noise (lightening/darkening), new for each row and frame
    // (The original hashes uint(coord.y * time * 5); this keeps the inputs small for float precision.)
    float n_interference = hash13(float3(floor(coord.y), pmod(floor(t * 60.0), 4096.0), 17.0));
    float inter = n_primary * analog_glitch_interference_magnitude;
    col.rgb = lerp(col.rgb, float3(n_interference, n_interference, n_interference), float3(inter, inter, inter));

    // Static lines (correlated to primary displacement)
    if (floor(pmod(coord.y * 0.25, 2.0)) < 0.001) {
        float intf = 1.0 - (analog_glitch_line_magnitude * n_primary);
        col.rgb *= intf;
        if (analog_glitch_interfence_alpha) {
            col.a = col.a - (1.0 - intf);
        }
    }

    return col;
}

technique Draw { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSAnalogGlitch(v_in); } }
