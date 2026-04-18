import Foundation
import Accelerate
import CoreImage

actor ToneMapper {
    static let shared = ToneMapper()
    
    // Mertens exposure fusion-based tone mapping
    func toneMap(image: CIImage, contrastWeight: Float = 1.0, saturationWeight: Float = 1.0, exposureWeight: Float = 1.0) -> CIImage {
        guard let cgImage = CIContext().createCGImage(image, from: image.extent) else {
            return image
        }
        
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        let totalBytes = height * bytesPerRow
        
        guard let data = malloc(totalBytes) else { return image }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            free(data)
            return image
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        let ptr = data.assumingMemoryBound(to: UInt8.self)
        
        // Compute luminance
        var luminance = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * bytesPerRow + x * 4
                let r = Float(ptr[idx])
                let g = Float(ptr[idx + 1])
                let b = Float(ptr[idx + 2])
                luminance[y * width + x] = 0.299 * r + 0.587 * g + 0.114 * b
            }
        }
        
        // Local tone mapping using bilateral-like filtering
        let sigmaSpatial: Float = 5.0
        let sigmaRange: Float = 30.0
        
        var toneMapped = [Float](repeating: 0, count: width * height * 4)
        
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * bytesPerRow + x * 4
                let centerLum = luminance[y * width + x]
                
                var sumR: Float = 0, sumG: Float = 0, sumB: Float = 0
                var weightSum: Float = 0
                
                let radius = Int(sigmaSpatial * 2)
                for dy in -radius...radius {
                    for dx in -radius...radius {
                        let ny = y + dy
                        let nx = x + dx
                        guard ny >= 0 && ny < height && nx >= 0 && nx < width else { continue }
                        
                        let nIdx = ny * bytesPerRow + nx * 4
                        let nLum = luminance[ny * width + nx]
                        
                        let spatialDist = Float(dx * dx + dy * dy)
                        let rangeDist = (centerLum - nLum) * (centerLum - nLum)
                        
                        let spatialWeight = exp(-spatialDist / (2 * sigmaSpatial * sigmaSpatial))
                        let rangeWeight = exp(-rangeDist / (2 * sigmaRange * sigmaRange))
                        let weight = spatialWeight * rangeWeight
                        
                        sumR += weight * Float(ptr[nIdx])
                        sumG += weight * Float(ptr[nIdx + 1])
                        sumB += weight * Float(ptr[nIdx + 2])
                        weightSum += weight
                    }
                }
                
                let invWeight = 1.0 / max(weightSum, 0.001)
                
                // Detail enhancement: original - base + enhanced
                let detailR = Float(ptr[idx]) - sumR * invWeight
                let detailG = Float(ptr[idx + 1]) - sumG * invWeight
                let detailB = Float(ptr[idx + 2]) - sumB * invWeight
                
                let baseR = sumR * invWeight
                let baseG = sumG * invWeight
                let baseB = sumB * invWeight
                
                // Compress base, enhance detail
                let compression: Float = 0.7
                let detailBoost: Float = 1.5
                
                let outIdx = (y * width + x) * 4
                toneMapped[outIdx] = max(0, min(255, baseR * compression + detailR * detailBoost + 128 * (1 - compression)))
                toneMapped[outIdx + 1] = max(0, min(255, baseG * compression + detailG * detailBoost + 128 * (1 - compression)))
                toneMapped[outIdx + 2] = max(0, min(255, baseB * compression + detailB * detailBoost + 128 * (1 - compression)))
                toneMapped[outIdx + 3] = 255
            }
        }
        
        // Convert back to CGImage
        let outData = malloc(totalBytes)!
        let outPtr = outData.assumingMemoryBound(to: UInt8.self)
        for i in 0..<(width * height * 4) {
            outPtr[i] = UInt8(toneMapped[i])
        }
        
        guard let outProvider = CGDataProvider(data: Data(bytesNoCopy: outData, count: totalBytes, deallocator: .free) as CFData),
              let outCgImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: outProvider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            free(data)
            free(outData)
            return image
        }
        
        free(data)
        return CIImage(cgImage: outCgImage)
    }
    
    func applyGamma(image: CIImage, gamma: Float) -> CIImage {
        return image.applyingFilter("CIGammaAdjust", parameters: ["inputPower": gamma])
    }
    
    func applyContrast(image: CIImage, contrast: Float) -> CIImage {
        return image.applyingFilter("CIColorControls", parameters: [
            "inputContrast": contrast,
            "inputSaturation": 1.0,
            "inputBrightness": 0
        ])
    }
}
