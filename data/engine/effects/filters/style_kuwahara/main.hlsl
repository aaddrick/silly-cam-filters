// Kuwahara Oil Paint: anisotropic Kuwahara filter in three passes.
//   tensor:  structure tensor (Sobel gradients) of the picture, at half size
//   blurred: smooth the tensor (separable blur, alternating direction)
//   paint:   8-sector Kuwahara on an ellipse that follows the local edge direction;
//            each sector is weighted by 1 / (1 + variance^q), so flat regions
//            get painted flat and edges stay sharp.

uniform float radius;
uniform float boost;

uniform texture2d tensor;
uniform texture2d blurred;

uniform float2 pass_texel;
uniform int iteration;

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

#define sharpness 8.0
#define stretch 0.6

float4 src(float2 uv)
{
    return image.Sample(textureSampler, uv);
}

float lum(float3 c)
{
    return dot(c, float3(0.299, 0.587, 0.114));
}

float4 PSTensor(VertData v_in) : TARGET
{
    float2 d = float2(upixel, vpixel) * 1.5;
    float l00 = lum(image.Sample(textureSampler, v_in.uv + float2(-d.x, -d.y)).rgb);
    float l10 = lum(image.Sample(textureSampler, v_in.uv + float2(0.0, -d.y)).rgb);
    float l20 = lum(image.Sample(textureSampler, v_in.uv + float2(d.x, -d.y)).rgb);
    float l01 = lum(image.Sample(textureSampler, v_in.uv + float2(-d.x, 0.0)).rgb);
    float l21 = lum(image.Sample(textureSampler, v_in.uv + float2(d.x, 0.0)).rgb);
    float l02 = lum(image.Sample(textureSampler, v_in.uv + float2(-d.x, d.y)).rgb);
    float l12 = lum(image.Sample(textureSampler, v_in.uv + float2(0.0, d.y)).rgb);
    float l22 = lum(image.Sample(textureSampler, v_in.uv + float2(d.x, d.y)).rgb);
    float gx = (l20 + 2.0 * l21 + l22) - (l00 + 2.0 * l01 + l02);
    float gy = (l02 + 2.0 * l12 + l22) - (l00 + 2.0 * l10 + l20);
    return float4(gx * gx, gx * gy, gy * gy, 1.0);
}

float4 PSBlur(VertData v_in) : TARGET
{
    float2 dir = (iteration % 2 == 0) ? float2(pass_texel.x, 0.0) : float2(0.0, pass_texel.y);
    dir *= 1.5;
    float3 acc = float3(0.0, 0.0, 0.0);
    float wsum = 0.0;
    for (int i = -4; i <= 4; i++) {
        float w = exp(-float(i * i) / 8.0);
        float2 p = v_in.uv + dir * float(i);
        if (iteration == 0)
            acc += tensor.Sample(textureSampler, p).rgb * w;
        else
            acc += blurred.Sample(textureSampler, p).rgb * w;
        wsum += w;
    }
    return float4(acc / wsum, 1.0);
}

float4 PSPaint(VertData v_in) : TARGET
{
    float4 center = image.Sample(textureSampler, v_in.uv);

    // Edge direction from the smoothed structure tensor
    float3 t = blurred.Sample(textureSampler, v_in.uv).rgb;
    float E = t.x, F = t.y, G = t.z;
    float disc = sqrt((E - G) * (E - G) + 4.0 * F * F);
    float l1 = 0.5 * (E + G + disc);
    float l2 = 0.5 * (E + G - disc);
    float aniso = (l1 - l2) / (l1 + l2 + 0.0001);
    float phi = 0.5 * atan2(2.0 * F, E - G);   // gradient direction
    // strokes run along the edge, perpendicular to the gradient
    float2 gdir = float2(cos(phi), sin(phi));
    float2 tdir = float2(-gdir.y, gdir.x);
    float elong = 1.0 + stretch * 2.0 * aniso;
    float squash = 1.0 / elong;

    float4 m[8];
    float4 s[8];
    for (int k = 0; k < 8; k++) {
        m[k] = float4(0.0, 0.0, 0.0, 0.0);
        s[k] = float4(0.0, 0.0, 0.0, 0.0);
    }

    const int N = 5;
    for (int j = -N; j <= N; j++) {
        for (int i = -N; i <= N; i++) {
            float2 q = float2(float(i), float(j)) / float(N);
            float r2 = dot(q, q);
            if (r2 <= 1.0) {
                float2 e = q.x * elong * tdir + q.y * squash * gdir;
                float2 uv = v_in.uv + e * radius * float2(upixel, vpixel);
                float3 c = src(uv).rgb;
                float l = lum(c);
                float ang = atan2(q.y, q.x);
                float g = exp(-r2 * 1.5);
                for (int k = 0; k < 8; k++) {
                    float ak = float(k) * 0.785398;
                    float dd = abs(fmod(ang - ak + 9.424778, 6.283185) - 3.141593);
                    float w = saturate(1.0 - dd / 0.785398 * 0.85) * g;
                    if (r2 == 0.0) w = g;
                    m[k] += float4(c * w, w);
                    s[k] += float4(l * l * w, l * w, 0.0, 0.0);
                }
            }
        }
    }

    float3 acc = float3(0.0, 0.0, 0.0);
    float wsum = 0.0;
    for (int k = 0; k < 8; k++) {
        float w = max(m[k].w, 0.0001);
        float3 mean = m[k].rgb / w;
        float ml = s[k].y / w;
        float sd = sqrt(max(s[k].x / w - ml * ml, 0.0));
        float wk = 1.0 / (1.0 + pow(sd * 60.0, sharpness));
        acc += mean * wk;
        wsum += wk;
    }
    float3 outc = acc / max(wsum, 0.0001);
    // colour boost: saturation only, black level and brightness are kept
    float g = lum(outc);
    outc = saturate(lerp(float3(g, g, g), outc, 1.0 + boost));
    return float4(outc, center.a);
}

technique Tensor { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSTensor(v_in); } }
technique Blur   { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSBlur(v_in); } }
technique Paint  { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSPaint(v_in); } }
