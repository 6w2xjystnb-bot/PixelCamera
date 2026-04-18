import Foundation
import Accelerate
import CoreImage

actor Dehazer {
    static let shared = Dehazer()
    
    // Dark channel prior dehazing with veiling glare removal
    func dehaze(image: CIImage, omega: Float = 0.95, t0: Float = 0.1) -> CIImage {
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
        
        // Compute dark channel
        let patchSize = 15
        var darkChannel = [UInt8](repeating: 255, count: width * height)
        
        for y in 0..<height {
            for x in 0..<width {
                var minVal: UInt8 = 255
                let yStart = max(0, y - patchSize / 2)
                let yEnd = min(height - 1, y + patchSize / 2)
                let xStart = max(0, x - patchSize / 2)
                let xEnd = min(width - 1, x + patchSize / 2)
                
                for py in yStart...yEnd {
                    for px in xStart...xEnd {
                        let idx = py * bytesPerRow + px * 4
                        let dark = min(ptr[idx], min(ptr[idx + 1], ptr[idx + 2]))
                        if dark < minVal { minVal = dark }
                    }
                }
                
                darkChannel[y * width + x] = minVal
            }
        }
        
        // Estimate atmospheric light (top 0.1% brightest pixels in dark channel)
        let sortedDark = darkChannel.enumerated().sorted { $0.element > $1.element }
        let topCount = max(1, width * height / 1000)
        
        var atmR: Float = 0, atmG: Float = 0, atmB: Float = 0
        for i in 0..<topCount {
            let idx = sortedDark[i].offset
            let pixelIdx = idx * 4
            atmR += Float(ptr[pixelIdx])
            atmG += Float(ptr[pixelIdx + 1])
            atmB += Float(ptr[pixelIdx + 2])
        }
        atmR /= Float(topCount)
        atmG /= Float(topCount)
        atmB /= Float(topCount)
        
        // Estimate transmission
        var transmission = [Float](repeating: 1.0, count: width * height)
        
        for y in 0..<height {
            for x in 0..<width {
                let dark = Float(darkChannel[y * width + x])
                transmission[y * width + x] = 1.0 - omega * dark / max(atmR, max(atmG, atmB))
            }
        }
        
        // Guided filter transmission (simplified box filter)
        transmission = boxFilter(transmission, width: width, height: height, radius: 20)
        
        // Recover scene radiance
        let outData = malloc(totalBytes)!
        let outPtr = outData.assumingMemoryBound(to: UInt8.self)
        
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * bytesPerRow + x * 4
                let t = max(transmission[y * width + x], t0)
                
                let r = (Float(ptr[idx]) - atmR) / t + atmR
                let g = (Float(ptr[idx + 1]) - atmG) / t + atmG
                let b = (Float(ptr[idx + 2]) - atmB) / t + atmB
                
                outPtr[idx] = UInt8(max(0, min(255, r)))
                outPtr[idx + 1] = UInt8(max(0, min(255, g)))
                outPtr[idx + 2] = UInt8(max(0, min(255, b)))
                outPtr[idx + 3] = 255
            }
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
    
    private func boxFilter(_ data: [Float], width: Int, height: Int, radius: Int) -> [Float] {
        var result = [Float](repeating: 0, count: width * height)
        
        // Horizontal pass
        var temp = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            var sum: Float = 0
            let r = radius
            
            for x in -r..<width + r {
                if x + r < width {
                    sum += data[y * width + min(x + r, width - 1)]
                }
                if x - r - 1 >= 0 {
                    sum -= data[y * width + max(x - r - 1, 0)]
                }
                if x >= 0 && x < width {
                    temp[y * width + x] = sum / Float(2 * r + 1)
                }
            }
        }
        
        // Vertical pass
        for x in 0..<width {
            var sum: Float = 0
            let r = radius
            
            for y in -r..<height + r {
                if y + r < height {
                    sum += temp[min(y + r, height - 1) * width + x]
                }
                if y - r - 1 >= 0 {
                    sum -= temp[max(y - r - 1, 0) * width + x]
                }
                if y >= 0 && y < height {
                    result[y * width + x] = sum / Float(2 * r + 1)
                }
            }
        }
        
        return result
    }
    
    func removeVeilingGlare(image: CIImage, strength: Float = 0.5) -> CIImage {
        // Simplified veiling glare removal via local minimum subtraction
        guard let cgImage = CIContext().createCGImage(image, from: image.extent) else { return image }
        
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
        
        let outData = malloc(totalBytes)!
        let outPtr = outData.assumingMemoryBound(to: UInt8.self)
        
        let radius = 25
        
        for y in 0..<height {
            for x in 0..<width {
                var minR = UInt8.max
                var minG = UInt8.max
                var minB = UInt8.max
                
                let yStart = max(0, y - radius)
                let yEnd = min(height - 1, y + radius)
                let xStart = max(0, x - radius)
                let xEnd = min(width - 1, x + radius)
                
                for py in yStart...yEnd {
                    for px in xStart...xEnd {
                        let idx = py * bytesPerRow + px * 4
                        if ptr[idx] < minR { minR = ptr[idx] }
                        if ptr[idx + 1] < minG { minG = ptr[idx + 1] }
                        if ptr[idx + 2] < minB { minB = ptr[idx + 2] }
                    }
                }
                
                let idx = y * bytesPerRow + x * 4
                let r = Float(ptr[idx]) - strength * Float(minR)
                let g = Float(ptr[idx + 1]) - strength * Float(minG)
                let b = Float(ptr[idx + 2]) - strength * Float(minB)
                
                outPtr[idx] = UInt8(max(0, min(255, r + strength * Float(minR) * 0.5)))
                outPtr[idx + 1] = UInt8(max(0, min(255, g + strength * Float(minG) * 0.5)))
                outPtr[idx + 2] = UInt8(max(0, min(255, b + strength * Float(minB) * 0.5)))
                outPtr[idx + 3] = 255
            }
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
}
