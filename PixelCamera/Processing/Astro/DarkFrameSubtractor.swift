import Foundation
import CoreImage
import Accelerate

actor DarkFrameSubtractor {
    static let shared = DarkFrameSubtractor()
    
    // Hot pixel removal using median of nearby frames
    func subtractDarkFrames(images: [CIImage]) -> [CIImage] {
        guard images.count >= 3 else { return images }
        
        let context = CIContext()
        guard let refCG = context.createCGImage(images[0], from: images[0].extent) else { return images }
        
        let width = refCG.width
        let height = refCG.height
        let bytesPerRow = width * 4
        let totalBytes = height * bytesPerRow
        
        // Build dark frame from temporal median
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
        
        guard buffers.count >= 3 else { return images }
        
        // Detect hot pixels (pixels that are consistently much brighter than neighbors)
        var hotPixelMask = [Bool](repeating: false, count: width * height)
        
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let idx = y * width + x
                let pixelIdx = y * bytesPerRow + x * 4
                
                // Check if this pixel is hot in most frames
                var hotCount = 0
                for buffer in buffers {
                    let lum = Int(buffer[pixelIdx]) + Int(buffer[pixelIdx + 1]) + Int(buffer[pixelIdx + 2])
                    
                    // Compare with 8 neighbors
                    var neighborSum = 0
                    var neighborCount = 0
                    for dy in -1...1 {
                        for dx in -1...1 {
                            if dx == 0 && dy == 0 { continue }
                            let nIdx = (y + dy) * bytesPerRow + (x + dx) * 4
                            neighborSum += Int(buffer[nIdx]) + Int(buffer[nIdx + 1]) + Int(buffer[nIdx + 2])
                            neighborCount += 1
                        }
                    }
                    
                    let neighborAvg = neighborSum / max(neighborCount, 1)
                    if lum > neighborAvg * 3 {
                        hotCount += 1
                    }
                }
                
                if hotCount >= buffers.count / 2 {
                    hotPixelMask[idx] = true
                }
            }
        }
        
        // Interpolate hot pixels from neighbors
        var cleanedImages: [CIImage] = []
        
        for buffer in buffers {
            let outData = malloc(totalBytes)!
            let outPtr = outData.assumingMemoryBound(to: UInt8.self)
            memcpy(outPtr, buffer, totalBytes)
            
            for y in 1..<(height - 1) {
                for x in 1..<(width - 1) {
                    let idx = y * width + x
                    guard hotPixelMask[idx] else { continue }
                    
                    let pixelIdx = y * bytesPerRow + x * 4
                    
                    var sumR = 0, sumG = 0, sumB = 0
                    var count = 0
                    
                    for dy in -1...1 {
                        for dx in -1...1 {
                            if dx == 0 && dy == 0 { continue }
                            let nIdx = (y + dy) * width + (x + dx)
                            guard !hotPixelMask[nIdx] else { continue }
                            let nPixelIdx = (y + dy) * bytesPerRow + (x + dx) * 4
                            sumR += Int(buffer[nPixelIdx])
                            sumG += Int(buffer[nPixelIdx + 1])
                            sumB += Int(buffer[nPixelIdx + 2])
                            count += 1
                        }
                    }
                    
                    if count > 0 {
                        outPtr[pixelIdx] = UInt8(sumR / count)
                        outPtr[pixelIdx + 1] = UInt8(sumG / count)
                        outPtr[pixelIdx + 2] = UInt8(sumB / count)
                    }
                }
            }
            
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let outProvider = CGDataProvider(data: Data(bytesNoCopy: outData, count: totalBytes, deallocator: .free) as CFData),
                  let outCgImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: outProvider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
                free(outData)
                continue
            }
            
            cleanedImages.append(CIImage(cgImage: outCgImage))
        }
        
        for buffer in buffers {
            free(buffer)
        }
        
        return cleanedImages.isEmpty ? images : cleanedImages
    }
}
