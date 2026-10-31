#include <metal_stdlib>
using namespace metal;

struct SceneVertex { float4 position; float4 color; };
struct SceneUniforms { float4x4 viewProjection; };
struct SceneVarying { float4 position [[position]]; float4 color; float distance; };

vertex SceneVarying sceneVertex(uint id [[vertex_id]],
                               const device SceneVertex* vertices [[buffer(0)]],
                               constant SceneUniforms& camera [[buffer(1)]]) {
    SceneVarying out;
    out.position = camera.viewProjection * vertices[id].position;
    out.distance = out.position.w;
    out.color = vertices[id].color;
    return out;
}
fragment float4 sceneFragment(SceneVarying in [[stage_in]]) {
    float fog = smoothstep(12.0, 36.0, in.distance);
    return float4(mix(in.color.rgb, float3(0.025, 0.035, 0.055), fog * 0.85), 1);
}
