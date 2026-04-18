import Foundation
import CoreImage
import Accelerate

actor StarStacker {
    static let shared = StarStacker()
    
    // Align and stack stars while preserving foreground
    func stackStars(images: [CIImage]) -> CIImage {
        guard let reference = images.first else { return CIImage() }
        
        let context = CIContext()
        guard let refCG = context.createCGImage(reference, from: reference.extent) else { return reference }
        
        let width = refCG.width
        let height = refCG.height
        let bytesPerRow = width * 4
        let totalBytes = height * bytesPerRow
        
        var buffers: [UnsafeMutablePointer<UInt8>] = []
        for image in images {
            guard let cgImage = context.createCGImage(image, from: image.extent) else { continue }
            guard let data = malloc(totalBytes) else { continue }
            
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let ctx = CGContext(data: data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                free(data)
                continue
            }
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            buffers.append(data.assumingMemoryBound(to: UInt8.self))
        }
        
        guard !buffers.isEmpty else { return reference }
        
        let outData = malloc(totalBytes)!
        let outPtr = outData.assumingMemoryBound(to: Float.self)
        
        // Detect foreground (brighter, sharper regions near bottom of frame typically)
        var foregroundMask = [Float](repeating: 0, count: width * height)
        
        // Simple foreground detection: pixels that are bright and consistent across frames
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                var sumR: Float = 0, sumG: Float = 0, sumB: Float = 0
                var varR: Float = 0, varG: Float = 0, varB: Float = 0
                
                for buffer in buffers {
                    let pixelIdx = y * bytesPerRow + x * 4
                    sumR += Float(buffer[pixelIdx])
                    sumG += Float(buffer[pixelIdx + 1])
                    sumB += Float(buffer[pixelIdx + 2])
                }
                
                let avgR = sumR / Float(buffers.count)
                let avgG = sumG / Float(buffers.count)
                let avgB = sumB / Float(buffers.count)
                
                for buffer in buffers {
                    let pixelIdx = y * bytesPerRow + x * 4
                    let diffR = Float(buffer[pixelIdx]) - avgR
                    let diffG = Float(buffer[pixelIdx + 1]) - avgG
                    let diffB = Float(buffer[pixelIdx + 2]) - avgB
                    varR += diffR * diffR
                    varG += diffG * diffG
                    varB += diffB * diffB
                }
                
                let variance = (varR + varG + varB) / Float(buffers.count)
                let brightness = avgR + avgG + avgB
                
                // Foreground: bright and consistent (low variance)
                if brightness > 100 && variance < 500 {
                    foregroundMask[idx] = 1.0
                }
            }
        }
        
        // Stack with foreground preservation
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * width + x
                let pixelIdx = y * bytesPerRow + x * 4
                
                let isForeground = foregroundMask[idx] > 0.5
                
                if isForeground {
                    // Use single frame for foreground (first frame)
                    outPtr[pixelIdx] = Float(buffers[0][pixelIdx])
                    outPtr[pixelIdx + 1] = Float(buffers[0][pixelIdx + 1])
                    outPtr[pixelIdx + 2] = Float(buffers[0][pixelIdx + 2])
                } else {
                    // Stack stars with sigma clipping
                    var rValues: [Float] = []
                    var gValues: [Float] = []
                    var bValues: [Float] = []
                    
                    for buffer in buffers {
                        rValues.append(Float(buffer[pixelIdx]))
                        gValues.append(Float(buffer[pixelIdx + 1]))
                        bValues.append(Float(buffer[pixelIdx + 2]))
                    }
                    
                    let medianR = median(rValues)
                    let medianG = median(gValues)
                    let medianB = median(bValues)
                    
                    var sumR: Float = 0, sumG: Float = 0, sumB: Float = 0
                    var count = 0
                    
                    for i in 0..<buffers.count {
                        let diff = abs(rValues[i] - medianR) + abs(gValues[i] - medianG) + abs(bValues[i] - medianB)
                        if diff < 60 {
                            sumR += rValues[i]
                            sumG += gValues[i]
                            sumB += bValues[i]
                            count += 1
                        }
                    }
                    
                    count = max(count, 1)
                    outPtr[pixelIdx] = sumR / Float(count)
                    outPtr[pixelIdx + 1] = sumG / Float(count)
                    outPtr[pixelIdx + 2] = sumB / Float(count)
                }
                
                outPtr[pixelIdx + 3] = 255
            }
        }
        
        for buffer in buffers {
            free(buffer)
        }
        
        var finalData = malloc(totalBytes)!
        let finalPtr = finalData.assumingMemoryBound(to: UInt8.self)
        for i in 0..<(width * height * 4) {
            finalPtr[i] = UInt8(max(0, min(255, outPtr[i])))
        }
        free(outData)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let outProvider = CGDataProvider(data: Data(bytesNoCopy: finalData, count: totalBytes, deallocator: .free) as CFData),
              let outCgImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: outProvider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            free(finalData)
            return reference
        }
        
        return CIImage(cgImage: outCgImage)
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
}
