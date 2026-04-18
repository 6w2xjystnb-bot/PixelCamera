#include <metal_stdlib>
using namespace metal;

// MARK: - Noise Reduction (Bilateral Filter)

kernel void bilateral_filter_kernel(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    constant float& sigmaSpatial [[buffer(0)]],
    constant float& sigmaRange [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    uint width = input.get_width();
    uint height = input.get_height();
    
    if (gid.x >= width || gid.y >= height) return;
    
    float4 center = input.read(gid);
    
    int radius = int(sigmaSpatial * 2.0);
    float sigmaSpatialSq = sigmaSpatial * sigmaSpatial;
    float sigmaRangeSq = sigmaRange * sigmaRange;
    
    float3 sum = float3(0.0);
    float weightSum = 0.0;
    
    for (int dy = -radius; dy <= radius; dy++) {
        for (int dx = -radius; dx <= radius; dx++) {
            uint sx = clamp((int)gid.x + dx, 0, (int)width - 1);
            uint sy = clamp((int)gid.y + dy, 0, (int)height - 1);
            
            float4 sample = input.read(uint2(sx, sy));
            
            float distSq = float(dx * dx + dy * dy);
            float spatialWeight = exp(-distSq / (2.0 * sigmaSpatialSq));
            
            float colorDiff = length(center.rgb - sample.rgb);
            float rangeWeight = exp(-(colorDiff * colorDiff) / (2.0 * sigmaRangeSq));
            
            float weight = spatialWeight * rangeWeight;
            sum += sample.rgb * weight;
            weightSum += weight;
        }
    }
    
    float3 result = sum / max(weightSum, 0.001);
    output.write(float4(result, center.a), gid);
}

// MARK: - Temporal Stack with Outlier Rejection

kernel void temporal_stack_kernel(
    texture2d<float, access::read> frame0 [[texture(0)]],
    texture2d<float, access::read> frame1 [[texture(1)]],
    texture2d<float, access::read> frame2 [[texture(2)]],
    texture2d<float, access::read> frame3 [[texture(3)]],
    texture2d<float, access::write> output [[texture(4)]],
    constant int& frameCount [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    uint width = frame0.get_width();
    uint height = frame0.get_height();
    
    if (gid.x >= width || gid.y >= height) return;
    
    float4 c0 = frame0.read(gid);
    float4 c1 = frame1.read(gid);
    float4 c2 = frame2.read(gid);
    float4 c3 = frame3.read(gid);
    
    // Median approximation (component-wise)
    float3 values[4] = {c0.rgb, c1.rgb, c2.rgb, c3.rgb};
    
    // Simple sigma clipping: reject outliers
    float3 mean = (c0.rgb + c1.rgb + c2.rgb + c3.rgb) / 4.0;
    float3 varSum = float3(0.0);
    for (int i = 0; i < 4; i++) {
        float3 diff = values[i] - mean;
        varSum += diff * diff;
    }
    float3 std = sqrt(varSum / 4.0);
    
    float3 sum = float3(0.0);
    int count = 0;
    for (int i = 0; i < 4; i++) {
        float3 diff = abs(values[i] - mean);
        if (all(diff < std * 2.0 + 0.05)) {
            sum += values[i];
            count++;
        }
    }
    
    float3 result = count > 0 ? sum / float(count) : mean;
    output.write(float4(result, c0.a), gid);
}

// MARK: - Sharpen

kernel void unsharp_mask_kernel(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    constant float& amount [[buffer(0)]],
    constant float& radius [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    uint width = input.get_width();
    uint height = input.get_height();
    
    if (gid.x >= width || gid.y >= height) return;
    
    float4 center = input.read(gid);
    
    // Gaussian blur approximation (3x3)
    float4 blur = float4(0.0);
    float weights[9] = {1.0/16.0, 2.0/16.0, 1.0/16.0,
                        2.0/16.0, 4.0/16.0, 2.0/16.0,
                        1.0/16.0, 2.0/16.0, 1.0/16.0};
    int idx = 0;
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            uint sx = clamp((int)gid.x + dx, 0, (int)width - 1);
            uint sy = clamp((int)gid.y + dy, 0, (int)height - 1);
            blur += input.read(uint2(sx, sy)) * weights[idx];
            idx++;
        }
    }
    
    float3 detail = center.rgb - blur.rgb;
    float3 sharpened = center.rgb + detail * amount;
    
    output.write(float4(clamp(sharpened, 0.0, 1.0), center.a), gid);
}

// MARK: - Auto White Balance (Gray World)

kernel void gray_world_wb_kernel(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    constant float& gainR [[buffer(0)]],
    constant float& gainB [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    uint width = input.get_width();
    uint height = input.get_height();
    
    if (gid.x >= width || gid.y >= height) return;
    
    float4 color = input.read(gid);
    
    float3 balanced = color.rgb * float3(gainR, 1.0, gainB);
    
    output.write(float4(clamp(balanced, 0.0, 1.0), color.a), gid);
}
