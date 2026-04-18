import Foundation
import CoreImage
import Accelerate

actor HairRefiner {
    static let shared = HairRefiner()
    
    // Edge-aware hair and detail refinement using guided filter
    func refine(image: CIImage, matte: CIImage, original: CIImage) -> CIImage {
        guard let cgImage = CIContext().createCGImage(image, from: image.extent),
              let matteCG = CIContext().createCGImage(matte, from: matte.extent),
              let origCG = CIContext().createCGImage(original, from: original.extent) else {
            return image
        }
        
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        
        guard let imageData = malloc(height * bytesPerRow),
              let matteData = malloc(height * bytesPerRow),
              let origData = malloc(height * bytesPerRow) else {
            return image
        }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let imgCtx = CGContext(data: imageData, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let matteCtx = CGContext(data: matteData, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let origCtx = CGContext(data: origData, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            free(imageData); free(matteData); free(origData)
            return image
        }
        
        imgCtx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        matteCtx.draw(matteCG, in: CGRect(x: 0, y: 0, width: width, height: height))
        origCtx.draw(origCG, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        let imgPtr = imageData.assumingMemoryBound(to: UInt8.self)
        let mattePtr = matteData.assumingMemoryBound(to: UInt8.self)
        let origPtr = origData.assumingMemoryBound(to: UInt8.self)
        
        let outData = malloc(height * bytesPerRow)!
        let outPtr = outData.assumingMemoryBound(to: UInt8.self)
        
        // Edge detection on original for guidance
        var edgeMap = [Float](repeating: 0, count: width * height)
        
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let idx = y * bytesPerRow + x * 4
                let lum = Float(origPtr[idx]) * 0.299 + Float(origPtr[idx + 1]) * 0.587 + Float(origPtr[idx + 2]) * 0.114
                
                let leftIdx = y * bytesPerRow + (x - 1) * 4
                let rightIdx = y * bytesPerRow + (x + 1) * 4
                let upIdx = (y - 1) * bytesPerRow + x * 4
                let downIdx = (y + 1) * bytesPerRow + x * 4
                
                let leftLum = Float(origPtr[leftIdx]) * 0.299 + Float(origPtr[leftIdx + 1]) * 0.587 + Float(origPtr[leftIdx + 2]) * 0.114
                let rightLum = Float(origPtr[rightIdx]) * 0.299 + Float(origPtr[rightIdx + 1]) * 0.587 + Float(origPtr[rightIdx + 2]) * 0.114
                let upLum = Float(origPtr[upIdx]) * 0.299 + Float(origPtr[upIdx + 1]) * 0.587 + Float(origPtr[upIdx + 2]) * 0.114
                let downLum = Float(origPtr[downIdx]) * 0.299 + Float(origPtr[downIdx + 1]) * 0.587 + Float(origPtr[downIdx + 2]) * 0.114
                
                let gx = abs(rightLum - leftLum)
                let gy = abs(downLum - upLum)
                edgeMap[y * width + x] = min(1.0, (gx + gy) / 50.0)
            }
        }
        
        // Refine edges using guided filter concept
        let radius = 3
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * bytesPerRow + x * 4
                let matteVal = Float(mattePtr[idx]) / 255.0
                let edgeVal = edgeMap[y * width + x]
                
                // Near edges, blend more toward original
                let edgeBlend = edgeVal * 0.7
                let preserveOriginal = matteVal * 0.3 + edgeBlend
                
                let finalR = Float(imgPtr[idx]) * (1 - preserveOriginal) + Float(origPtr[idx]) * preserveOriginal
                let finalG = Float(imgPtr[idx + 1]) * (1 - preserveOriginal) + Float(origPtr[idx + 1]) * preserveOriginal
                let finalB = Float(imgPtr[idx + 2]) * (1 - preserveOriginal) + Float(origPtr[idx + 2]) * preserveOriginal
                
                outPtr[idx] = UInt8(max(0, min(255, finalR)))
                outPtr[idx + 1] = UInt8(max(0, min(255, finalG)))
                outPtr[idx + 2] = UInt8(max(0, min(255, finalB)))
                outPtr[idx + 3] = 255
            }
        }
        
        guard let outProvider = CGDataProvider(data: Data(bytesNoCopy: outData, count: height * bytesPerRow, deallocator: .free) as CFData),
              let outCgImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: outProvider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            free(imageData); free(matteData); free(origData); free(outData)
            return image
        }
        
        free(imageData); free(matteData); free(origData)
        return CIImage(cgImage: outCgImage)
    }
}
