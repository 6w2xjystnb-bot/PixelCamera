import Foundation
import CoreImage
import Accelerate

actor NoiseReducer {
    static let shared = NoiseReducer()
    
    // Multi-scale noise reduction using bilateral filter pyramid
    func reduceNoise(image: CIImage, strength: Float = 0.8) -> CIImage {
        guard let cgImage = CIContext().createCGImage(image, from: image.extent) else { return image }
        
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        
        guard let data = malloc(height * bytesPerRow) else { return image }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            free(data)
            return image
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Apply multi-scale bilateral filtering
        var result = bilateralFilter(buffer: data, width: width, height: height, sigmaSpatial: 3, sigmaRange: 30)
        
        // Coarse scale
        let coarse = bilateralFilter(buffer: data, width: width, height: height, sigmaSpatial: 7, sigmaRange: 50)
        
        // Blend scales
        result = blendBuffers(base: result, detail: coarse, width: width, height: height, alpha: 0.3)
        
        let outImage = bufferToCIImage(buffer: result, width: width, height: height)
        free(data)
        free(result.data)
        free(coarse.data)
        
        return outImage
    }
    
    private func bilateralFilter(buffer: UnsafeMutableRawPointer, width: Int, height: Int, sigmaSpatial: Float, sigmaRange: Float) -> vImage_Buffer {
        let bytesPerRow = width * 4
        let totalBytes = height * bytesPerRow
        let outData = malloc(totalBytes)!
        
        let src = buffer.assumingMemoryBound(to: UInt8.self)
        let dst = outData.assumingMemoryBound(to: UInt8.self)
        
        let radius = Int(sigmaSpatial * 2)
        let sigmaSq = sigmaSpatial * sigmaSpatial
        let rangeSq = sigmaRange * sigmaRange
        
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * bytesPerRow + x * 4
                let centerR = Float(src[idx])
                let centerG = Float(src[idx + 1])
                let centerB = Float(src[idx + 2])
                
                var sumR: Float = 0, sumG: Float = 0, sumB: Float = 0
                var weightSum: Float = 0
                
                for dy in -radius...radius {
                    for dx in -radius...radius {
                        let ny = y + dy
                        let nx = x + dx
                        guard ny >= 0 && ny < height && nx >= 0 && nx < width else { continue }
                        
                        let nIdx = ny * bytesPerRow + nx * 4
                        let distSq = Float(dx * dx + dy * dy)
                        let spatialWeight = exp(-distSq / (2 * sigmaSq))
                        
                        let nR = Float(src[nIdx])
                        let nG = Float(src[nIdx + 1])
                        let nB = Float(src[nIdx + 2])
                        
                        let colorDiff = (centerR - nR) * (centerR - nR) +
                                       (centerG - nG) * (centerG - nG) +
                                       (centerB - nB) * (centerB - nB)
                        let rangeWeight = exp(-colorDiff / (2 * rangeSq))
                        
                        let weight = spatialWeight * rangeWeight
                        sumR += nR * weight
                        sumG += nG * weight
                        sumB += nB * weight
                        weightSum += weight
                    }
                }
                
                let invW = 1.0 / max(weightSum, 0.001)
                dst[idx] = UInt8(max(0, min(255, sumR * invW)))
                dst[idx + 1] = UInt8(max(0, min(255, sumG * invW)))
                dst[idx + 2] = UInt8(max(0, min(255, sumB * invW)))
                dst[idx + 3] = 255
            }
        }
        
        return vImage_Buffer(data: outData, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: bytesPerRow)
    }
    
    private func blendBuffers(base: vImage_Buffer, detail: vImage_Buffer, width: Int, height: Int, alpha: Float) -> vImage_Buffer {
        let bytesPerRow = width * 4
        let totalBytes = height * bytesPerRow
        let outData = malloc(totalBytes)!
        let dst = outData.assumingMemoryBound(to: UInt8.self)
        let basePtr = base.data.assumingMemoryBound(to: UInt8.self)
        let detailPtr = detail.data.assumingMemoryBound(to: UInt8.self)
        
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * bytesPerRow + x * 4
                dst[idx] = UInt8(max(0, min(255, Float(basePtr[idx]) * (1 - alpha) + Float(detailPtr[idx]) * alpha)))
                dst[idx + 1] = UInt8(max(0, min(255, Float(basePtr[idx + 1]) * (1 - alpha) + Float(detailPtr[idx + 1]) * alpha)))
                dst[idx + 2] = UInt8(max(0, min(255, Float(basePtr[idx + 2]) * (1 - alpha) + Float(detailPtr[idx + 2]) * alpha)))
                dst[idx + 3] = 255
            }
        }
        
        return vImage_Buffer(data: outData, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: bytesPerRow)
    }
    
    private func bufferToCIImage(buffer: vImage_Buffer, width: Int, height: Int) -> CIImage {
        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: Data(bytesNoCopy: buffer.data, count: height * bytesPerRow, deallocator: .none) as CFData),
              let cgImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            return CIImage()
        }
        return CIImage(cgImage: cgImage)
    }
    
    func sharpen(image: CIImage, amount: Float = 0.5) -> CIImage {
        return image.applyingFilter("CISharpenLuminance", parameters: ["inputSharpness": amount])
    }
}
