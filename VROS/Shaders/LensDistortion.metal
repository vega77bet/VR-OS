#include <metal_stdlib>
using namespace metal;

struct LensVarying { float4 position [[position]]; float2 uv; };
struct LensUniforms {
    float2 center;
    float2 imageOffset;
    float2 imageScale;
    float2 tangential;
    float rotationRadians;
    float aspect;
    float radialK1;
    float radialK2;
    float radialK3;
    float distortionStrength;
    float chromaticRedScale;
    float chromaticBlueScale;
};

vertex LensVarying lensVertex(uint id [[vertex_id]]) {
    const float2 positions[] = { float2(-1,-1), float2(3,-1), float2(-1,3) };
    LensVarying out;
    out.position = float4(positions[id], 0, 1);
    // Metal viewport and texture origin are top-left.
    out.uv = float2((positions[id].x + 1) * 0.5, (1 - positions[id].y) * 0.5);
    return out;
}

inline float2 mapLensUV(float2 normalized, constant LensUniforms& lens, float chromaticScale) {
    float x = normalized.x;
    float y = normalized.y;
    float r2 = dot(normalized, normalized);
    float radial = 1 + lens.distortionStrength *
        (lens.radialK1 * r2 + lens.radialK2 * r2 * r2 + lens.radialK3 * r2 * r2 * r2);
    float p1 = lens.tangential.x;
    float p2 = lens.tangential.y;
    float tx = 2 * p1 * x * y + p2 * (r2 + 2 * x * x);
    float ty = p1 * (r2 + 2 * y * y) + 2 * p2 * x * y;
    float2 corrected = float2((x * radial + tx) * chromaticScale,
                              (y * radial + ty) * chromaticScale);
    return lens.center + float2(corrected.x / (2 * lens.aspect), corrected.y / 2);
}

inline float2 applyImageScale(float2 correctedUV, float2 center, float2 imageScale) {
    float2 safeScale = max(imageScale, float2(0.001));
    return center + (correctedUV - center) / safeScale;
}

fragment float4 lensFragment(LensVarying in [[stage_in]],
                             constant LensUniforms& lens [[buffer(0)]],
                             texture2d<float> source [[texture(0)]]) {
    float2 delta = in.uv - lens.center - lens.imageOffset;
    float c = cos(-lens.rotationRadians);
    float s = sin(-lens.rotationRadians);
    delta = float2(c * delta.x - s * delta.y, s * delta.x + c * delta.y);
    float2 normalized = 2 * delta * float2(lens.aspect, 1);
    // Keep image scale as the final placement operation after lens warp. This
    // preserves the legacy VR-OS profile semantics while remaining an inverse
    // map: each output pixel still asks for one source coordinate.
    float2 uv = applyImageScale(mapLensUV(normalized, lens, 1), lens.center, lens.imageScale);
    float2 redUV = applyImageScale(mapLensUV(normalized, lens, lens.chromaticRedScale),
                                   lens.center, lens.imageScale);
    float2 blueUV = applyImageScale(mapLensUV(normalized, lens, lens.chromaticBlueScale),
                                    lens.center, lens.imageScale);
    if (any(uv < 0) || any(uv > 1) || any(redUV < 0) || any(redUV > 1) ||
        any(blueUV < 0) || any(blueUV > 1)) return float4(0, 0, 0, 1);
    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float4 greenSample = source.sample(linearSampler, uv);
    if (lens.chromaticRedScale == 1 && lens.chromaticBlueScale == 1) {
        return float4(greenSample.rgb, 1);
    }
    float4 redSample = source.sample(linearSampler, redUV);
    float4 blueSample = source.sample(linearSampler, blueUV);
    return float4(redSample.r, greenSample.g, blueSample.b, 1);
}
