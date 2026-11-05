// Retro: Codec (old FMV / RPZA)
// Port of the Retro Codec filter from obs-retro-effects 1.0.2 by FiniteSingularity.
// RPZA shader by Millennium Cyborg, loosely based on ffmpeg's RPZA encoder
// (https://ffmpeg.org/doxygen/trunk/rpzaenc_8c_source.html). GPL-2.0, as the original.
//
// The original renders at (width / px_scale) x (height / px_scale), keeps that output as the
// "previous frame", and area-upscales it. Pass sizes are fixed in this engine, so this port
// renders at full size and works on a virtual grid of floor(size / px_scale) pixels: each
// output pixel computes the RPZA result of the virtual pixel that contains it. The pass reads
// its own output of the previous frame (codec_out) as the previous encoded frame.
// The keyframe timer becomes: a keyframe on the first frame, and each time elapsed_time
// crosses a multiple of the keyframe interval.

uniform int codec_type;
uniform float codec_px_scale;
uniform int codec_colors_per_channel;
uniform float codec_quality;
uniform float codec_keyframe_interval;
uniform bool codec_custom_thresholds;
uniform float codec_rpza_threshold_prev_frame;
uniform float codec_rpza_threshold_solid;
uniform float codec_rpza_threshold_gradient;

uniform float elapsed_time;
uniform float2 uv_size;

// This pass's own output of the previous frame, bound by the engine.
uniform texture2d codec_out;

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

float pmod(float x, float y)
{
    return x - y * floor(x / y);
}

float2 virtual_size()
{
    return max(floor(uv_size / max(codec_px_scale, 1.0)), float2(1.0, 1.0));
}

float2 uvFromPx(float2 px)
{
    return (px + 0.5) / virtual_size();
}

float4 sampleSource(float2 px)
{
    // Bilinear downscale, as the original's first step
    return image.Sample(textureSampler, uvFromPx(px));
}

float4 samplePrev(float2 px)
{
    return codec_out.Sample(pointSampler, uvFromPx(px));
}

float3 quantize(float3 color, float dither)
{
    float cpc = float(codec_colors_per_channel);
    return floor(color * cpc + dither) / cpc;
}

// 4x4 Bayer matrix {0,8,2,10, 12,4,14,6, 3,11,1,9, 15,7,13,5} without an array
float bayer2(float2 p)
{
    return 2.0 * p.x + 3.0 * p.y - 4.0 * p.x * p.y;
}

float get_bayer(float2 px)
{
    float2 a = float2(pmod(px.x, 2.0), pmod(px.y, 2.0));
    float2 b = float2(pmod(floor(px.x / 2.0), 2.0), pmod(floor(px.y / 2.0), 2.0));
    return (4.0 * bayer2(a) + bayer2(b)) / 16.0;
}

float4 sampleWithDither(float2 px)
{
    float4 col = sampleSource(px);
    col.rgb = quantize(col.rgb, get_bayer(px));
    return col;
}

float comp3(float3 v, int i)
{
    if (i == 0) return v.x;
    if (i == 1) return v.y;
    return v.z;
}

// rotate components
float3 rotateCol(float3 col, int amount)
{
    if (amount == 0) return col;
    if (amount == 1) return col.gbr;
    return col.brg;
}

float calcSquareError(float3 ref_col, float3 col)
{
    float3 d = saturate(abs(col - ref_col));
    return dot(d, d);
}

// Least-squares gradient over the 4x4 block, as in the original (and ffmpeg's RPZA encoder):
// the channel with the largest range is the primary; the others are regressed against it.
void calcGradient(float2 blockCoord, out float3 mean, out float3 startCol, out float3 endCol)
{
    float3 minCol = float3(1.0, 1.0, 1.0);
    float3 maxCol = float3(0.0, 0.0, 0.0);
    float3 sum = float3(0.0, 0.0, 0.0);
    float3 sumSq = float3(0.0, 0.0, 0.0);
    float3 sumProd = float3(0.0, 0.0, 0.0); // bg, gr, rb

    for (int bx = 0; bx < 4; bx++) {
        for (int by = 0; by < 4; by++) {
            float2 px = blockCoord * 4.0 + float2(float(bx), float(by));
            float3 col = sampleWithDither(px).rgb;
            minCol = min(minCol, col);
            maxCol = max(maxCol, col);
            sum += col;
            sumSq += col * col;
            sumProd += float3(col.b * col.g, col.g * col.r, col.r * col.b);
        }
    }

    int maxChanIdx = 0;
    float maxChanRange = 0.0;
    float3 chanRange = abs(minCol - maxCol);
    if (chanRange.x > maxChanRange) { maxChanIdx = 0; maxChanRange = chanRange.x; }
    if (chanRange.y > maxChanRange) { maxChanIdx = 1; maxChanRange = chanRange.y; }
    if (chanRange.z > maxChanRange) { maxChanIdx = 2; maxChanRange = chanRange.z; }

    float3 maxChanMask = float3(maxChanIdx == 0 ? 1.0 : 0.0, maxChanIdx == 1 ? 1.0 : 0.0, maxChanIdx == 2 ? 1.0 : 0.0);

    sumProd = rotateCol(sumProd, maxChanIdx);

    float sumMax = comp3(sum, maxChanIdx);
    float d = 16.0 * comp3(sumSq, maxChanIdx) - sumMax * sumMax;

    mean = sum / 16.0;

    if (abs(d) < 0.00001) {
        // All the pixels in the block are the same color or very close.
        startCol = mean;
        endCol = mean;
    } else {
        float3 m = (16.0 * sumProd - sumMax * sum) / d;
        float3 b = (sum - m * sumMax) / 16.0;
        startCol = lerp(m * comp3(minCol, maxChanIdx) + b, minCol, maxChanMask);
        endCol = lerp(m * comp3(maxCol, maxChanIdx) + b, maxCol, maxChanMask);
    }

    startCol = saturate(startCol);
    endCol = saturate(endCol);
}

float3 closestGradCol(float3 g0, float3 g1, float3 g2, float3 g3, float3 col, out float minErr)
{
    float3 best = g0;
    minErr = calcSquareError(g0, col);
    float e = calcSquareError(g1, col);
    if (e < minErr) { minErr = e; best = g1; }
    e = calcSquareError(g2, col);
    if (e < minErr) { minErr = e; best = g2; }
    e = calcSquareError(g3, col);
    if (e < minErr) { minErr = e; best = g3; }
    return best;
}

bool isKeyframe()
{
    if (frame_index <= 0) {
        return true;
    }
    if (codec_keyframe_interval > 0.0) {
        float now = floor(elapsed_time / codec_keyframe_interval);
        float before = floor((elapsed_time - delta_time) / codec_keyframe_interval);
        return now != before;
    }
    return false;
}

float3 rpzaEncode(float2 sourcePx)
{
    float2 blockCoord = floor(sourcePx / 4.0);

    float th_prev = codec_rpza_threshold_prev_frame;
    float th_solid = codec_rpza_threshold_solid;
    float th_grad = codec_rpza_threshold_gradient;
    if (!codec_custom_thresholds) {
        th_prev = lerp(0.5, 0.0, codec_quality);
        th_solid = lerp(0.2, 0.0, codec_quality);
        th_grad = lerp(1.0, 0.0, codec_quality);
    }

    float3 mean = float3(0.0, 0.0, 0.0);
    float3 startCol = float3(0.0, 0.0, 0.0);
    float3 endCol = float3(1.0, 1.0, 1.0);
    calcGradient(blockCoord, mean, startCol, endCol);

    mean = quantize(mean, 0.0);
    startCol = quantize(startCol, 0.0);
    endCol = quantize(endCol, 0.0);

    // 4-color gradient
    float3 g0 = quantize(startCol, 0.0);
    float3 g1 = quantize(lerp(startCol, endCol, 1.0 / 3.0), 0.0);
    float3 g2 = quantize(lerp(startCol, endCol, 2.0 / 3.0), 0.0);
    float3 g3 = quantize(endCol, 0.0);

    float sumSqErr0 = 0.0;
    float sumSqErr1 = 0.0;
    float sumSqErr4 = 0.0;

    for (int bx = 0; bx < 4; bx++) {
        for (int by = 0; by < 4; by++) {
            float2 px = blockCoord * 4.0 + float2(float(bx), float(by));
            float3 col = sampleWithDither(px).rgb;
            sumSqErr0 += calcSquareError(col, samplePrev(px).rgb);
            sumSqErr1 += calcSquareError(col, mean);
            float minErr = 0.0;
            float3 unused = closestGradCol(g0, g1, g2, g3, col, minErr);
            sumSqErr4 += minErr;
        }
    }

    float3 c = sampleWithDither(sourcePx).rgb;

    // option 0: keep previous block
    if (!isKeyframe() && sumSqErr0 < th_prev * th_prev) {
        return samplePrev(sourcePx).rgb;
    }

    // option 1: single color
    if (sumSqErr1 < th_solid * th_solid) {
        return mean;
    }

    // option 2: 4 colors
    if (sumSqErr4 < th_grad * th_grad) {
        float e = 0.0;
        return closestGradCol(g0, g1, g2, g3, c, e);
    }

    // option 3: 16 colors
    return c;
}

float4 PSRPZA(VertData v_in) : TARGET
{
    // codec_type has a single value (RPZA) in the original.
    float2 px = floor(v_in.uv * virtual_size());
    float4 col = sampleWithDither(px);
    col.rgb = rpzaEncode(px);
    return col;
}

technique RPZA { pass { vertex_shader = VSDefault(v_in); pixel_shader = PSRPZA(v_in); } }
