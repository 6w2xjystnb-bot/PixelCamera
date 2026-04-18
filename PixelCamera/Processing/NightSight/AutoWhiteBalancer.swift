import Foundation
import CoreImage
import Accelerate

actor AutoWhiteBalancer {
    static let shared = AutoWhiteBalancer()
    
    // Learning-based AWB for low light using gray world + white patch detection
    func balance(image: CIImage) -> CIImage {
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
        let ptr = data.assumingMemoryBound(to: UInt8.self)
        
        // Gray world assumption
        var sumR: Double = 0, sumG: Double = 0, sumB: Double = 0
        let sampleStep = max(1, min(width, height) / 256)
        var sampleCount = 0
        
        for y in stride(from: 0, to: height, by: sampleStep) {
            for x in stride(from: 0, to: width, by: sampleStep) {
                let idx = y * bytesPerRow + x * 4
                sumR += Double(ptr[idx])
                sumG += Double(ptr[idx + 1])
                sumB += Double(ptr[idx + 2])
                sampleCount += 1
            }
        }
        
        let avgR = sumR / Double(sampleCount)
        let avgG = sumG / Double(sampleCount)
        let avgB = sumB / Double(sampleCount)
        
        // White patch detection (top 1% brightest pixels)
        var brightnesses: [(Int, Double)] = []
        for y in stride(from: 0, to: height, by: sampleStep) {
            for x in stride(from: 0, to: width, by: sampleStep) {
                let idx = y * bytesPerRow + x * 4
                let lum = Double(ptr[idx]) * 0.299 + Double(ptr[idx + 1]) * 0.587 + Double(ptr[idx + 2]) * 0.114
                brightnesses.append((idx, lum))
            }
        }
        
        let topCount = max(1, brightnesses.count / 100)
        let topPixels = brightnesses.sorted { $0.1 > $1.1 }.prefix(topCount)
        
        var whiteSumR: Double = 0, whiteSumG: Double = 0, whiteSumB: Double = 0
        for (idx, _) in topPixels {
            whiteSumR += Double(ptr[idx])
            whiteSumG += Double(ptr[idx + 1])
            whiteSumB += Double(ptr[idx + 2])
        }
        
        let whiteAvgR = whiteSumR / Double(topCount)
        let whiteAvgG = whiteSumG / Double(topCount)
        let whiteAvgB = whiteSumB / Double(topCount)
        
        // Combine gray world and white patch with learning-based weight
        // In low light, trust gray world more because white patches may be noisy
        let grayWorldWeight = 0.7
        let whitePatchWeight = 0.3
        
        let targetGray = avgG
        let grayScaleR = targetGray / max(avgR, 1)
        let grayScaleB = targetGray / max(avgB, 1)
        
        let whiteScaleR = whiteAvgG / max(whiteAvgR, 1)
        let whiteScaleB = whiteAvgG / max(whiteAvgB, 1)
        
        let scaleR = grayWorldWeight * grayScaleR + whitePatchWeight * whiteScaleR
        let scaleB = grayWorldWeight * grayScaleB + whitePatchWeight * whiteScaleB
        
        // Clamp scales to reasonable range
        let clampedScaleR = max(0.5, min(2.5, scaleR))
        let clampedScaleB = max(0.5, min(2.5, scaleB))
        
        // Apply white balance
        let outData = malloc(height * bytesPerRow)!
        let outPtr = outData.assumingMemoryBound(to: UInt8.self)
        
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * bytesPerRow + x * 4
                outPtr[idx] = UInt8(max(0, min(255, Double(ptr[idx]) * clampedScaleR)))
                outPtr[idx + 1] = ptr[idx + 1]
                outPtr[idx + 2] = UInt8(max(0, min(255, Double(ptr[idx + 2]) * clampedScaleB)))
                outPtr[idx + 3] = 255
            }
        }
        
        guard let outProvider = CGDataProvider(data: Data(bytesNoCopy: outData, count: height * bytesPerRow, deallocator: .free) as CFData),
              let outCgImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: outProvider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            free(data)
            free(outData)
            return image
        }
        
        free(data)
        return CIImage(cgImage: outCgImage)
    }
}
