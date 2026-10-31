#include <metal_stdlib>
using namespace metal;

struct LensVarying { float4 position [[position]]; float2 uv; };
struct LensUniforms {
    float2 center;
    float scale;
    float aspect;
    float k1;
    float k2;
    float strength;
    float padding;
};

vertex LensVarying lensVertex(uint id [[vertex_id]]) {
    const float2 positions[] = { float2(-1,-1), float2(3,-1), float2(-1,3) };
    LensVarying out;
    out.position = float4(positions[id], 0, 1);
    // Metal viewport and texture origin are top-left.
    out.uv = float2((positions[id].x + 1) * 0.5, (1 - positions[id].y) * 0.5);
    return out;
}

fragment float4 lensFragment(LensVarying in [[stage_in]],
                             constant LensUniforms& lens [[buffer(0)]],
                             texture2d<float> source [[texture(0)]]) {
    float2 delta = in.uv - lens.center;
    float2 radial = 2 * delta * float2(lens.aspect, 1);
    float radius2 = dot(radial, radial);
    // Inverse sampling produces a barrel prewarp for typical pincushion VR lenses.
    // These coefficients are provisional and deliberately user-adjustable.
    float factor = 1 + lens.strength * (lens.k1 * radius2 + lens.k2 * radius2 * radius2);
    float2 uv = lens.center + delta * factor / lens.scale;
    if (any(uv < 0) || any(uv > 1)) return float4(0, 0, 0, 1);
    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    return float4(source.sample(linearSampler, uv).rgb, 1);
}
