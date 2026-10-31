#include <metal_stdlib>
using namespace metal;

struct SpatialVertex { float4 position; float4 color; float2 uv; float2 padding; };
struct SpatialCamera { float4x4 viewProjection; };
struct SpatialVarying { float4 position [[position]]; float4 color; float2 uv; };

vertex SpatialVarying spatialVertex(uint id [[vertex_id]],
                                    const device SpatialVertex* vertices [[buffer(0)]],
                                    constant SpatialCamera& camera [[buffer(1)]]) {
    SpatialVarying out;
    out.position = camera.viewProjection * vertices[id].position;
    out.color = vertices[id].color;
    out.uv = vertices[id].uv;
    return out;
}

fragment float4 spatialFragment(SpatialVarying in [[stage_in]], texture2d<float> atlas [[texture(0)]]) {
    constexpr sampler glyphSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    const float4 glyph = atlas.sample(glyphSampler, in.uv);
    // Atlas samples already carry premultiplied alpha. Preserve that convention for blending.
    return float4(glyph.rgb * in.color.rgb * in.color.a, glyph.a * in.color.a);
}
