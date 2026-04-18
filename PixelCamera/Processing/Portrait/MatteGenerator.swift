import Foundation
import CoreImage
import Accelerate

actor MatteGenerator {
    static let shared = MatteGenerator()
    
    func generateMatte(from depthImage: CIImage, image: CIImage) -> CIImage {
        guard let cgImage = CIContext().createCGImage(depthImage, from: depthImage.extent) else {
            return depthImage
        }
        
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        
        guard let data = malloc(height * bytesPerRow) else { return depthImage }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            free(data)
            return depthImage
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let ptr = data.assumingMemoryBound(to: UInt8.self)
        
        // Threshold depth to separate foreground/background
        // Foreground = closer = higher depth values typically
        var foregroundMask = [UInt8](repeating: 0, count: width * height)
        
        // Compute depth histogram to find threshold
        var histogram = [Int](repeating: 0, count: 256)
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * bytesPerRow + x * 4
                let gray = UInt8((Int(ptr[idx]) + Int(ptr[idx + 1]) + Int(ptr[idx + 2])) / 3)
                histogram[Int(gray)] += 1
            }
        }
        
        // Otsu's threshold
        let threshold = otsuThreshold(histogram: histogram, totalPixels: width * height)
        
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * bytesPerRow + x * 4
                let gray = (Int(ptr[idx]) + Int(ptr[idx + 1]) + Int(ptr[idx + 2])) / 3
                
                // Foreground = closer = higher values
                let alpha = gray > threshold ? 255 : 0
                foregroundMask[y * width + x] = UInt8(alpha)
            }
        }
        
        // Dilate and erode to clean up
        foregroundMask = morphologicalClose(mask: foregroundMask, width: width, height: height, radius: 3)
        
        // Feather edges
        foregroundMask = featherEdges(mask: foregroundMask, width: width, height: height, radius: 5)
        
        let outData = malloc(height * bytesPerRow)!
        let outPtr = outData.assumingMemoryBound(to: UInt8.self)
        
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * bytesPerRow + x * 4
                let alpha = foregroundMask[y * width + x]
                outPtr[idx] = alpha
                outPtr[idx + 1] = alpha
                outPtr[idx + 2] = alpha
                outPtr[idx + 3] = 255
            }
        }
        
        guard let outProvider = CGDataProvider(data: Data(bytesNoCopy: outData, count: height * bytesPerRow, deallocator: .free) as CFData),
              let outCgImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: outProvider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            free(data)
            free(outData)
            return depthImage
        }
        
        free(data)
        return CIImage(cgImage: outCgImage)
    }
    
    private func otsuThreshold(histogram: [Int], totalPixels: Int) -> Int {
        var sum: Double = 0
        for i in 0..<256 {
            sum += Double(i) * Double(histogram[i])
        }
        
        var sumB: Double = 0
        var wB = 0
        var maxVariance: Double = 0
        var threshold = 128
        
        for i in 0..<256 {
            wB += histogram[i]
            if wB == 0 { continue }
            
            let wF = totalPixels - wB
            if wF == 0 { break }
            
            sumB += Double(i) * Double(histogram[i])
            let mB = sumB / Double(wB)
            let mF = (sum - sumB) / Double(wF)
            let variance = Double(wB) * Double(wF) * (mB - mF) * (mB - mF)
            
            if variance > maxVariance {
                maxVariance = variance
                threshold = i
            }
        }
        
        return threshold
    }
    
    private func morphologicalClose(mask: [UInt8], width: Int, height: Int, radius: Int) -> [UInt8] {
        // Dilate then erode
        let dilated = dilate(mask: mask, width: width, height: height, radius: radius)
        return erode(mask: dilated, width: width, height: height, radius: radius)
    }
    
    private func dilate(mask: [UInt8], width: Int, height: Int, radius: Int) -> [UInt8] {
        var result = mask
        for y in 0..<height {
            for x in 0..<width {
                var maxVal: UInt8 = 0
                for dy in -radius...radius {
                    for dx in -radius...radius {
                        let ny = y + dy
                        let nx = x + dx
                        if ny >= 0 && ny < height && nx >= 0 && nx < width {
                            maxVal = max(maxVal, mask[ny * width + nx])
                        }
                    }
                }
                result[y * width + x] = maxVal
            }
        }
        return result
    }
    
    private func erode(mask: [UInt8], width: Int, height: Int, radius: Int) -> [UInt8] {
        var result = mask
        for y in 0..<height {
            for x in 0..<width {
                var minVal: UInt8 = 255
                for dy in -radius...radius {
                    for dx in -radius...radius {
                        let ny = y + dy
                        let nx = x + dx
                        if ny >= 0 && ny < height && nx >= 0 && nx < width {
                            minVal = min(minVal, mask[ny * width + nx])
                        }
                    }
                }
                result[y * width + x] = minVal
            }
        }
        return result
    }
    
    private func featherEdges(mask: [UInt8], width: Int, height: Int, radius: Int) -> [UInt8] {
        var result = mask
        for y in 0..<height {
            for x in 0..<width {
                var sum: Float = 0
                var count = 0
                for dy in -radius...radius {
                    for dx in -radius...radius {
                        let ny = y + dy
                        let nx = x + dx
                        if ny >= 0 && ny < height && nx >= 0 && nx < width {
                            let dist = sqrt(Float(dx * dx + dy * dy))
                            let weight = max(0, 1 - dist / Float(radius))
                            sum += Float(mask[ny * width + nx]) * weight
                            count += 1
                        }
                    }
                }
                result[y * width + x] = UInt8(max(0, min(255, sum / Float(count))))
            }
        }
        return result
    }
}
