// Fluid Smoke: stable fluids on a 128x72 grid (rgba16f, signed values).
//   vel:      advect last frame's velocity, add a force estimated from camera motion, damp, add buoyancy
//   div:      divergence of vel
//   pressure: 20 Jacobi iterations (each starts from zero pressure)
//   project:  vel minus the pressure gradient (divergence free)
//   dye:      advect last frame's dye along project, inject colour where the picture moves, fade
//   out:      add the smoke to the picture
// Velocities are in grid texels per frame and are clamped to +-3. Dye is clamped to 0..1.5.

uniform float motion_threshold;
uniform float force;
uniform float dissipation;
uniform float rise;
uniform float4 dye_color;
uniform bool rainbow;
uniform float strength;
uniform bool smoke_only;

uniform texture2d image_prev;
uniform texture2d project_prev;
uniform texture2d dye_prev;
uniform texture2d vel;
uniform texture2d div;
uniform texture2d pressure;
uniform texture2d project;
uniform texture2d dye;

uniform float2 pass_texel;
uniform int iteration;

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

float lum(float3 c) { return dot(c, float3(0.299, 0.587, 0.114)); }

// Smoothed luma of the source (or its previous frame) over a small cross, in grid units.
float src_luma(float2 uv, float2 o)
{
    float a = lum(image.Sample(textureSampler, uv + o).rgb) + lum(image.Sample(textureSampler, uv - o).rgb)
            + lum(image.Sample(textureSampler, uv + float2(o.x, -o.y)).rgb) + lum(image.Sample(textureSampler, uv + float2(-o.x, o.y)).rgb);
    return a * 0.25;
}
float prev_luma(float2 uv, float2 o)
{
    float a = lum(image_prev.Sample(textureSampler, uv + o).rgb) + lum(image_prev.Sample(textureSampler, uv - o).rgb)
            + lum(image_prev.Sample(textureSampler, uv + float2(o.x, -o.y)).rgb) + lum(image_prev.Sample(textureSampler, uv + float2(-o.x, o.y)).rgb);
    return a * 0.25;
}

// x = motion mask 0..1, yz = motion direction in grid texels per frame (brightness-constancy estimate)
float3 motion_at(float2 uv)
{
    float2 o = pass_texel * 1.5;
    float it = src_luma(uv, o) - prev_luma(uv, o);
    float gx = 0.5 * (lum(image.Sample(textureSampler, uv + float2(pass_texel.x * 2.0, 0.0)).rgb) - lum(image.Sample(textureSampler, uv - float2(pass_texel.x * 2.0, 0.0)).rgb)) / 2.0;
    float gy = 0.5 * (lum(image.Sample(textureSampler, uv + float2(0.0, pass_texel.y * 2.0)).rgb) - lum(image.Sample(textureSampler, uv - float2(0.0, pass_texel.y * 2.0)).rgb)) / 2.0;
    float g2 = gx * gx + gy * gy + 0.0004;
    float2 flow = -it * float2(gx, gy) / g2;
    float len = length(flow);
    if (len > 3.0) flow *= 3.0 / len;
    float m = smoothstep(motion_threshold, motion_threshold * 2.5, abs(it));
    return float3(m, flow);
}

float4 PSVel(VertData v_in) : TARGET
{
    float2 uv = v_in.uv;
    float2 v0 = project_prev.Sample(textureSampler, uv).xy;
    float2 back = uv - v0 * pass_texel;
    float2 v = project_prev.Sample(textureSampler, back).xy;
    float3 mo = motion_at(uv);
    v += mo.yz * mo.x * force;
    float d = dye_prev.Sample(textureSampler, uv).a;
    v.y -= rise * d * 0.15;
    v *= 0.985;
    float len = length(v);
    if (len > 3.0) v *= 3.0 / len;
    return float4(v, 0.0, 1.0);
}

float4 PSDiv(VertData v_in) : TARGET
{
    float2 uv = v_in.uv;
    float l = vel.Sample(pointSampler, uv - float2(pass_texel.x, 0.0)).x;
    float r = vel.Sample(pointSampler, uv + float2(pass_texel.x, 0.0)).x;
    float t = vel.Sample(pointSampler, uv - float2(0.0, pass_texel.y)).y;
    float b = vel.Sample(pointSampler, uv + float2(0.0, pass_texel.y)).y;
    return float4(0.5 * (r - l + b - t), 0.0, 0.0, 1.0);
}

float4 PSPressure(VertData v_in) : TARGET
{
    float2 uv = v_in.uv;
    float dv = div.Sample(pointSampler, uv).x;
    float p = 0.0;
    if (iteration > 0) {
        p = pressure.Sample(pointSampler, uv - float2(pass_texel.x, 0.0)).x
          + pressure.Sample(pointSampler, uv + float2(pass_texel.x, 0.0)).x
          + pressure.Sample(pointSampler, uv - float2(0.0, pass_texel.y)).x
          + pressure.Sample(pointSampler, uv + float2(0.0, pass_texel.y)).x;
    }
    return float4((p - dv) * 0.25, 0.0, 0.0, 1.0);
}

float4 PSProject(VertData v_in) : TARGET
{
    float2 uv = v_in.uv;
    float l = pressure.Sample(pointSampler, uv - float2(pass_texel.x, 0.0)).x;
    float r = pressure.Sample(pointSampler, uv + float2(pass_texel.x, 0.0)).x;
    float t = pressure.Sample(pointSampler, uv - float2(0.0, pass_texel.y)).x;
    float b = pressure.Sample(pointSampler, uv + float2(0.0, pass_texel.y)).x;
    float2 v = vel.Sample(pointSampler, uv).xy - 0.5 * float2(r - l, b - t);
    float len = length(v);
    if (len > 3.0) v *= 3.0 / len;
    return float4(v, 0.0, 1.0);
}

float3 hue(float h)
{
    float3 k = frac(float3(h, h + 0.6667, h + 0.3333));
    return saturate(abs(k * 6.0 - 3.0) - 1.0);
}

float4 PSDye(VertData v_in) : TARGET
{
    float2 uv = v_in.uv;
    float2 v = project.Sample(textureSampler, uv).xy;
    float4 d = dye_prev.Sample(textureSampler, uv - v * pass_texel);
    d *= dissipation;
    float3 mo = motion_at(uv);
    float3 col = rainbow ? hue(float(frame_index) * 0.004) * 0.9 + 0.1 : dye_color.rgb;
    float amt = mo.x * 0.12;
    d.rgb = d.rgb + col * amt;
    d.a = max(d.a * dissipation, amt);
    d = clamp(d, 0.0, 1.5);
    return float4(d.rgb, saturate(max(d.r, max(d.g, d.b))));
}

float4 PSDraw(VertData v_in) : TARGET
{
    float4 base = image.Sample(textureSampler, v_in.uv);
    float3 s = dye.Sample(textureSampler, v_in.uv).rgb * strength;
    float3 rgb = smoke_only ? saturate(s) : 1.0 - (1.0 - base.rgb) * (1.0 - saturate(s));
    return float4(rgb, base.a);
}

technique Vel      { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSVel(v_in); } }
technique Div      { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSDiv(v_in); } }
technique Pressure { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSPressure(v_in); } }
technique Project  { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSProject(v_in); } }
technique Dye      { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSDye(v_in); } }
technique Draw     { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSDraw(v_in); } }
