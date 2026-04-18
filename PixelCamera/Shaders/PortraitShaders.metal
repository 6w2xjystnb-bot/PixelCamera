#include <metal_stdlib>
using namespace metal;

// MARK: - Bokeh Blur

kernel void hexagonal_bokeh_blur_kernel(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::read> depth [[texture(1)]],
    texture2d<float, access::read> matte [[texture(2)]],
    texture2d<float, access::write> output [[texture(3)]],
    constant int& maxRadius [[buffer(0)]],
    constant float& focusDepth [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    uint width = input.get_width();
    uint height = input.get_height();
    
    if (gid.x >= width || gid.y >= height) return;
    
    float4 color = input.read(gid);
    float4 depthVal = depth.read(gid);
    float4 matteVal = matte.read(gid);
    
    float matteAlpha = matteVal.r;
    float depthValue = depthVal.r;
    
    // Background blur amount
    float blurAmount = (1.0 - matteAlpha) * abs(depthValue - focusDepth);
    int radius = int(blurAmount * float(maxRadius));
    
    if (radius <= 1) {
        output.write(color, gid);
        return;
    }
    
    float3 sum = float3(0.0);
    float weightSum = 0.0;
    
    // Hexagonal kernel sampling
    for (int dy = -radius; dy <= radius; dy++) {
        for (int dx = -radius; dx <= radius; dx++) {
            int dist = abs(dx) + abs(dy);
            if (dist > radius * 2) continue;
            
            uint sx = clamp((int)gid.x + dx, 0, (int)width - 1);
            uint sy = clamp((int)gid.y + dy, 0, (int)height - 1);
            
            float hexWeight = max(0.0, 1.0 - float(dist) / float(radius));
            
            float4 sampleColor = input.read(uint2(sx, sy));
            sum += sampleColor.rgb * hexWeight;
            weightSum += hexWeight;
        }
    }
    
    float3 blurred = sum / max(weightSum, 0.001);
    
    // Blend based on matte
    float3 finalColor = color.rgb * matteAlpha + blurred * (1.0 - matteAlpha);
    
    output.write(float4(finalColor, color.a), gid);
}

// MARK: - Matte Refinement

kernel void matte_refinement_kernel(
    texture2d<float, access::read> matte [[texture(0)]],
    texture2d<float, access::read> edges [[texture(1)]],
    texture2d<float, access::write> output [[texture(2)]],
    constant float& edgeWeight [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    uint width = matte.get_width();
    uint height = matte.get_height();
    
    if (gid.x >= width || gid.y >= height) return;
    
    float4 matteVal = matte.read(gid);
    float4 edgeVal = edges.read(gid);
    
    // Use edges to refine matte boundaries
    float edgeStrength = length(edgeVal.rgb);
    float refined = matteVal.r;
    
    // Near edges, pull toward 0 or 1
    if (edgeStrength > 0.1) {
        refined = refined > 0.5 ? min(1.0, refined + edgeWeight) : max(0.0, refined - edgeWeight);
    }
    
    output.write(float4(refined, refined, refined, 1.0), gid);
}

// MARK: - Depth Estimation Helper

kernel void depth_from_edges_kernel(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    uint width = input.get_width();
    uint height = input.get_height();
    
    if (gid.x >= width || gid.y >= height) return;
    
    float4 center = input.read(gid);
    
    // Sobel edge detection
    float4 left = input.read(uint2(max(gid.x - 1, 0u), gid.y));
    float4 right = input.read(uint2(min(gid.x + 1, width - 1), gid.y));
    float4 up = input.read(uint2(gid.x, max(gid.y - 1, 0u)));
    float4 down = input.read(uint2(gid.x, min(gid.y + 1, height - 1)));
    
    float gx = length(right.rgb - left.rgb);
    float gy = length(down.rgb - up.rgb);
    float edge = sqrt(gx * gx + gy * gy);
    
    // Normalize
    float depth = 1.0 - clamp(edge * 2.0, 0.0, 1.0);
    
    output.write(float4(depth, depth, depth, 1.0), gid);
}
