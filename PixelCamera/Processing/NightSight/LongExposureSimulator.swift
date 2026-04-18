import Foundation
import CoreImage
import CoreVideo
import Accelerate

actor LongExposureSimulator {
    static let shared = LongExposureSimulator()
    
    // Stacks many short exposures with motion robustness
    func simulateLongExposure(images: [CIImage], motionData: [CMDeviceMotion]? = nil) async throws -> CIImage {
        guard images.count >= 3 else {
            throw CameraError.processingFailed("Need at least 3 frames")
        }
        
        let context = CIContext()
        let reference = images[0]
        guard let refCG = context.createCGImage(reference, from: reference.extent) else {
            throw CameraError.processingFailed("Failed to create reference CGImage")
        }
        
        let width = refCG.width
        let height = refCG.height
        let bytesPerRow = width * 4
        
        // Convert all images to aligned buffers
        var alignedBuffers: [vImage_Buffer] = []
        
        for (index, image) in images.enumerated() {
            guard let cgImage = context.createCGImage(image, from: image.extent) else { continue }
            
            let totalBytes = height * bytesPerRow
            guard let data = malloc(totalBytes) else { continue }
            
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let ctx = CGContext(data: data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                free(data)
                continue
            }
            
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            
            // If motion data available, apply compensation
            if let motions = motionData, index < motions.count, index > 0 {
                let prevMotion = motions[index - 1]
                let currentMotion = motions[index]
                let dx = Int((currentMotion.attitude.roll - prevMotion.attitude.roll) * 50)
                let dy = Int((currentMotion.attitude.pitch - prevMotion.attitude.pitch) * 50)
                
                let shifted = shiftBuffer(data: data, width: width, height: height, dx: dx, dy: dy)
                alignedBuffers.append(vImage_Buffer(data: shifted, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: bytesPerRow))
            } else {
                alignedBuffers.append(vImage_Buffer(data: data, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: bytesPerRow))
            }
        }
        
        guard !alignedBuffers.isEmpty else {
            throw CameraError.processingFailed("No valid buffers")
        }
        
        // Temporal average with outlier rejection
        let result = temporalAverageWithRejection(buffers: alignedBuffers, width: width, height: height)
        
        // Free buffers
        for buffer in alignedBuffers {
            free(buffer.data)
        }
        
        return bufferToCIImage(buffer: result, width: width, height: height)
    }
    
    private func shiftBuffer(data: UnsafeMutableRawPointer, width: Int, height: Int, dx: Int, dy: Int) -> UnsafeMutableRawPointer {
        let bytesPerRow = width * 4
        let totalBytes = height * bytesPerRow
        let shifted = malloc(totalBytes)!
        let src = data.assumingMemoryBound(to: UInt8.self)
        let dst = shifted.assumingMemoryBound(to: UInt8.self)
        
        for y in 0..<height {
            for x in 0..<width {
                let srcX = x + dx
                let srcY = y + dy
                let dstIdx = y * bytesPerRow + x * 4
                
                if srcX >= 0 && srcX < width && srcY >= 0 && srcY < height {
                    let srcIdx = srcY * bytesPerRow + srcX * 4
                    dst[dstIdx] = src[srcIdx]
                    dst[dstIdx + 1] = src[srcIdx + 1]
                    dst[dstIdx + 2] = src[srcIdx + 2]
                    dst[dstIdx + 3] = src[srcIdx + 3]
                } else {
                    dst[dstIdx] = 0
                    dst[dstIdx + 1] = 0
                    dst[dstIdx + 2] = 0
                    dst[dstIdx + 3] = 255
                }
            }
        }
        
        free(data)
        return shifted
    }
    
    private func temporalAverageWithRejection(buffers: [vImage_Buffer], width: Int, height: Int) -> vImage_Buffer {
        let bytesPerRow = width * 4
        let totalBytes = height * bytesPerRow
        let resultData = malloc(totalBytes)!
        let resultPtr = resultData.assumingMemoryBound(to: Float.self)
        
        let count = buffers.count
        
        for y in 0..<height {
            for x in 0..<width {
                let idx = (y * width + x) * 4
                var rValues: [Float] = []
                var gValues: [Float] = []
                var bValues: [Float] = []
                
                for buffer in buffers {
                    let ptr = buffer.data.assumingMemoryBound(to: UInt8.self)
                    let pixelIdx = y * bytesPerRow + x * 4
                    rValues.append(Float(ptr[pixelIdx]))
                    gValues.append(Float(ptr[pixelIdx + 1]))
                    bValues.append(Float(ptr[pixelIdx + 2]))
                }
                
                // Reject outliers (pixels too different from median)
                let medianR = median(rValues)
                let medianG = median(gValues)
                let medianB = median(bValues)
                
                var sumR: Float = 0, sumG: Float = 0, sumB: Float = 0
                var validCount = 0
                
                for i in 0..<count {
                    let diff = abs(rValues[i] - medianR) + abs(gValues[i] - medianG) + abs(bValues[i] - medianB)
                    if diff < 60 {
                        sumR += rValues[i]
                        sumG += gValues[i]
                        sumB += bValues[i]
                        validCount += 1
                    }
                }
                
                validCount = max(validCount, 1)
                resultPtr[idx] = sumR / Float(validCount)
                resultPtr[idx + 1] = sumG / Float(validCount)
                resultPtr[idx + 2] = sumB / Float(validCount)
                resultPtr[idx + 3] = 255
            }
        }
        
        var finalData = malloc(totalBytes)!
        let finalPtr = finalData.assumingMemoryBound(to: UInt8.self)
        for i in 0..<(width * height * 4) {
            finalPtr[i] = UInt8(max(0, min(255, resultPtr[i])))
        }
        free(resultData)
        
        return vImage_Buffer(data: finalData, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: bytesPerRow)
    }
    
    private func median(_ values: [Float]) -> Float {
        let sorted = values.sorted()
        let count = sorted.count
        if count % 2 == 0 {
            return (sorted[count / 2 - 1] + sorted[count / 2]) / 2
        } else {
            return sorted[count / 2]
        }
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
}
