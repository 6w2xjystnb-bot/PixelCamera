#include <metal_stdlib>
using namespace metal;

// MARK: - HDR+ Alignment

kernel void tile_alignment_kernel(
    texture2d<float, access::read> reference [[texture(0)]],
    texture2d<float, access::read> frame [[texture(1)]],
    texture2d<float, access::write> output [[texture(2)]],
    constant int& tileSize [[buffer(0)]],
    constant int& searchRadius [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    uint width = reference.get_width();
    uint height = reference.get_height();
    
    uint tilesX = (width + tileSize - 1) / tileSize;
    uint tileX = gid.x;
    uint tileY = gid.y;
    
    if (tileX >= tilesX || tileY >= (height + tileSize - 1) / tileSize) return;
    
    uint baseX = tileX * tileSize;
    uint baseY = tileY * tileSize;
    
    float bestScore = 1e10;
    int bestDx = 0;
    int bestDy = 0;
    
    // Search for best alignment
    for (int dy = -searchRadius; dy <= searchRadius; dy++) {
        for (int dx = -searchRadius; dx <= searchRadius; dx++) {
            float sad = 0.0;
            int count = 0;
            
            for (uint py = 0; py < tileSize; py++) {
                for (uint px = 0; px < tileSize; px++) {
                    uint x = baseX + px;
                    uint y = baseY + py;
                    
                    if (x >= width || y >= height) continue;
                    
                    uint fx = clamp((int)x + dx, 0, (int)width - 1);
                    uint fy = clamp((int)y + dy, 0, (int)height - 1);
                    
                    float4 refColor = reference.read(uint2(x, y));
                    float4 frameColor = frame.read(uint2(fx, fy));
                    
                    float diff = abs(refColor.r - frameColor.r) +
                                abs(refColor.g - frameColor.g) +
                                abs(refColor.b - frameColor.b);
                    sad += diff / 3.0;
                    count++;
                }
            }
            
            float score = count > 0 ? sad / float(count) : 1e10;
            if (score < bestScore) {
                bestScore = score;
                bestDx = dx;
                bestDy = dy;
            }
        }
    }
    
    // Store motion vector as RG, confidence as B
    float confidence = 1.0 - clamp(bestScore / 50.0, 0.0, 1.0);
    output.write(float4(float(bestDx) / 255.0, float(bestDy) / 255.0, confidence, 1.0), gid);
}

// MARK: - HDR+ Merge (Wiener Filter)

kernel void wiener_merge_kernel(
    texture2d<float, access::read> reference [[texture(0)]],
    texture2d<float, access::read> frame [[texture(1)]],
    texture2d<float, access::read> motion [[texture(2)]],
    texture2d<float, access::read_write> accumulator [[texture(3)]],
    texture2d<float, access::read_write> weightAccumulator [[texture(4)]],
    constant float& noiseVariance [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    uint width = reference.get_width();
    uint height = reference.get_height();
    
    if (gid.x >= width || gid.y >= height) return;
    
    float4 motionVec = motion.read(gid);
    float confidence = motionVec.b;
    
    if (confidence < 0.3) return;
    
    int dx = int(motionVec.r * 255.0);
    int dy = int(motionVec.g * 255.0);
    
    uint fx = clamp((int)gid.x + dx, 0, (int)width - 1);
    uint fy = clamp((int)gid.y + dy, 0, (int)height - 1);
    
    float4 refColor = reference.read(gid);
    float4 frameColor = frame.read(uint2(fx, fy));
    
    // Wiener filter weight
    float signalVar = dot(refColor.rgb, refColor.rgb) / 3.0;
    float wienerWeight = signalVar / (signalVar + noiseVariance);
    float blendWeight = wienerWeight * confidence;
    
    float4 current = accumulator.read(gid);
    float4 currentWeight = weightAccumulator.read(gid);
    
    accumulator.write(current + frameColor * blendWeight, gid);
    weightAccumulator.write(currentWeight + blendWeight, gid);
}

// MARK: - Tone Mapping (Local Gamma)

kernel void local_tone_map_kernel(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    constant float& gamma [[buffer(0)]],
    constant float& shadowBoost [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    uint width = input.get_width();
    uint height = input.get_height();
    
    if (gid.x >= width || gid.y >= height) return;
    
    float4 color = input.read(gid);
    
    // Perceptual luminance
    float lum = dot(color.rgb, float3(0.299, 0.587, 0.114));
    
    // Adaptive gamma based on local luminance
    float localGamma = gamma;
    if (lum < 0.3) {
        localGamma = gamma * (1.0 - shadowBoost * (0.3 - lum));
    }
    
    float3 mapped = pow(color.rgb, float3(localGamma));
    
    // Preserve saturation
    float mappedLum = dot(mapped, float3(0.299, 0.587, 0.114));
    if (mappedLum > 0.001) {
        mapped = mapped * (lum / mappedLum);
    }
    
    output.write(float4(mapped, color.a), gid);
}

// MARK: - Dehaze

kernel void dehaze_kernel(
    texture2d<float, access::read> input [[texture(0)]],
    texture2d<float, access::write> output [[texture(1)]],
    constant float3& atmosphericLight [[buffer(0)]],
    constant float& omega [[buffer(1)]],
    constant float& t0 [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]])
{
    uint width = input.get_width();
    uint height = input.get_height();
    
    if (gid.x >= width || gid.y >= height) return;
    
    float4 color = input.read(gid);
    
    // Simplified dark channel approximation
    float dark = min(color.r, min(color.g, color.b));
    float transmission = 1.0 - omega * dark / max(max(atmosphericLight.r, atmosphericLight.g), atmosphericLight.b);
    transmission = max(transmission, t0);
    
    float3 recovered = (color.rgb - atmosphericLight) / transmission + atmosphericLight;
    
    output.write(float4(clamp(recovered, 0.0, 1.0), color.a), gid);
}
