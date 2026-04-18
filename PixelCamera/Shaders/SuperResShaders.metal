#include <metal_stdlib>
using namespace metal;

// MARK: - Subpixel Shift

kernel void subpixel_shift_kernel(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    constant float& dx [[buffer(0)]],
    constant float& dy [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    uint width = input.get_width();
    uint height = input.get_height();
    
    if (gid.x >= width || gid.y >= height) return;
    
    float2 coord = float2(float(gid.x) + dx, float(gid.y) + dy);
    
    // Bilinear interpolation
    uint x0 = uint(clamp(floor(coord.x), 0.0, float(width) - 2));
    uint y0 = uint(clamp(floor(coord.y), 0.0, float(height) - 2));
    uint x1 = x0 + 1;
    uint y1 = y0 + 1;
    
    float fx = coord.x - floor(coord.x);
    float fy = coord.y - floor(coord.y);
    
    float4 c00 = input.read(uint2(x0, y0));
    float4 c10 = input.read(uint2(x1, y0));
    float4 c01 = input.read(uint2(x0, y1));
    float4 c11 = input.read(uint2(x1, y1));
    
    float4 top = mix(c00, c10, fx);
    float4 bottom = mix(c01, c11, fx);
    float4 result = mix(top, bottom, fy);
    
    output.write(result, gid);
}

// MARK: - Detail Reconstruction (Frequency Blending)

kernel void detail_reconstruction_kernel(
    texture2d<float, access::read> reference [[texture(0)]],
    texture2d<float, access::read> aligned1 [[texture(1)]],
    texture2d<float, access::read> aligned2 [[texture(2)]],
    texture2d<float, access::read> aligned3 [[texture(3)]],
    texture2d<float, access::write> output [[texture(4)]],
    uint2 gid [[thread_position_in_grid]])
{
    uint width = reference.get_width();
    uint height = reference.get_height();
    
    if (gid.x >= width || gid.y >= height) return;
    
    float4 ref = reference.read(gid);
    float4 a1 = aligned1.read(gid);
    float4 a2 = aligned2.read(gid);
    float4 a3 = aligned3.read(gid);
    
    // Temporal average (low frequency)
    float4 lowFreq = (ref + a1 + a2 + a3) / 4.0;
    
    // Find frame with highest local variance (most detail)
    float4 frames[4] = {ref, a1, a2, a3};
    float bestVar = 0.0;
    float4 bestDetail = ref;
    
    for (int i = 0; i < 4; i++) {
        float var = 0.0;
        for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
                uint sx = clamp((int)gid.x + dx, 0, (int)width - 1);
                uint sy = clamp((int)gid.y + dy, 0, (int)height - 1);
                float4 neighbor = frames[i];
                if (dx != 0 || dy != 0) {
                    // Read actual neighbor
                    if (i == 0) neighbor = reference.read(uint2(sx, sy));
                    else if (i == 1) neighbor = aligned1.read(uint2(sx, sy));
                    else if (i == 2) neighbor = aligned2.read(uint2(sx, sy));
                    else neighbor = aligned3.read(uint2(sx, sy));
                }
                float3 diff = frames[i].rgb - lowFreq.rgb;
                var += dot(diff, diff);
            }
        }
        if (var > bestVar) {
            bestVar = var;
            bestDetail = frames[i];
        }
    }
    
    // High frequency from sharpest frame
    float4 highFreq = bestDetail - lowFreq;
    
    // Blend low and high frequencies
    float lowRatio = 0.6;
    float highRatio = 0.4;
    
    float4 result = lowFreq + highFreq * (highRatio / lowRatio);
    
    output.write(clamp(result, 0.0, 1.0), gid);
}

// MARK: - Gradient Sharpening

kernel void gradient_sharpen_kernel(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    constant float& strength [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    uint width = input.get_width();
    uint height = input.get_height();
    
    if (gid.x >= width || gid.y >= height) return;
    
    float4 center = input.read(gid);
    
    // Laplacian
    float4 left = input.read(uint2(max(gid.x - 1, 0u), gid.y));
    float4 right = input.read(uint2(min(gid.x + 1, width - 1), gid.y));
    float4 up = input.read(uint2(gid.x, max(gid.y - 1, 0u)));
    float4 down = input.read(uint2(gid.x, min(gid.y + 1, height - 1)));
    
    float4 laplacian = left + right + up + down - 4.0 * center;
    
    float4 sharpened = center - laplacian * strength;
    
    output.write(clamp(sharpened, 0.0, 1.0), gid);
}
