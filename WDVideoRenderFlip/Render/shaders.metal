//
//  shaders.metal
//  VideoDemo
//
//  Created by ByteDance on 2023/12/25.
//

#include <metal_stdlib>
using namespace metal;

constant float3 kRec709Luma = float3(0.2126, 0.7152, 0.0722);

kernel void
flipShader(texture2d<float, access::read> in [[texture(0)]],
           texture2d<float, access::write> out [[texture(1)]],
           uint2 gid [[thread_position_in_grid]])
{
    float4 color = in.read(vector_uint2(in.get_width() - gid.x, gid.y));
    float gray = dot(color.rgb, kRec709Luma);
    out.write(float4(gray, gray, gray, 1.0), gid);
}
