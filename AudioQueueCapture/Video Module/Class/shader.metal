//
//  shader.metal
//  AudioQueueCapture
//
//  Created by admin on 2020/10/21.
//

#include <metal_stdlib>
using namespace metal;

#import "ShaderTypes.h"

typedef struct {
    float4 clipSpacePosition [[position]];
    float2 textureCoordinate;
} RasterizerData;

vertex RasterizerData
vertexShader(uint vertexID [[vertex_id]],
             constant PWMVertex *vertices [[buffer(0)]]) {
    RasterizerData out;

    out.clipSpacePosition = vector_float4(0, 0, 0, 1);
    out.clipSpacePosition.xy = vertices[vertexID].position.xy;
    out.textureCoordinate = vertices[vertexID].coordinate.xy;
    
    return out;
}

fragment float4
fragmentShader(RasterizerData in [[stage_in]],
               texture2d<half> texture [[texture(0)]]) {
    constexpr sampler textureSampler (mag_filter::linear,
                                      min_filter::linear);
    
    const half4 colorPixel = texture.sample(textureSampler, in.textureCoordinate);
    return float4(colorPixel);
}

kernel void
yuvToRGB(texture2d<float, access::read> yTexture[[texture(0)]],
         texture2d<float, access::read> uvTexture[[texture(1)]],
         texture2d<float, access::write> outTexture[[texture(2)]],
         constant float3x3 *convertMatrix [[buffer(0)]],
         uint2 gid [[thread_position_in_grid]]) {

    float4 ySample = yTexture.read(gid);
    float4 uvSample = uvTexture.read(gid/2);
    
    float3 yuv;
    yuv.x = ySample.r;
    yuv.yz = uvSample.rg - float2(0.5);
    
    float3x3 matrix = *convertMatrix;
    float3 rgb = matrix * yuv;
    outTexture.write(float4(rgb, yuv.x), gid);
}


