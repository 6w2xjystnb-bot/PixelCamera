import Foundation
import CoreImage
import Accelerate

actor BokehRenderer {
    static let shared = BokehRenderer()
    
    func renderBokeh(image: CIImage, depth: CIImage, matte: CIImage) -> CIImage {
        guard let cgImage = CIContext().createCGImage(image, from: image.extent),
              let depthCG = CIContext().createCGImage(depth, from: depth.extent),
              let matteCG = CIContext().createCGImage(matte, from: matte.extent) else {
            return image
        }
        
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        
        guard let imageData = malloc(height * bytesPerRow),
              let depthData = malloc(height * bytesPerRow),
              let matteData = malloc(height * bytesPerRow) else {
            return image
        }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        guard let imgCtx = CGContext(data: imageData, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let depthCtx = CGContext(data: depthData, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let matteCtx = CGContext(data: matteData, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            free(imageData); free(depthData); free(matteData)
            return image
        }
        
        imgCtx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        depthCtx.draw(depthCG, in: CGRect(x: 0, y: 0, width: width, height: height))
        matteCtx.draw(matteCG, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        let imgPtr = imageData.assumingMemoryBound(to: UInt8.self)
        let depthPtr = depthData.assumingMemoryBound(to: UInt8.self)
        let mattePtr = matteData.assumingMemoryBound(to: UInt8.self)
        
        let outData = malloc(height * bytesPerRow)!
        let outPtr = outData.assumingMemoryBound(to: UInt8.self)
        
        // Hexagonal bokeh kernel simulation
        let maxBlurRadius = 15
        
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * bytesPerRow + x * 4
                let matteVal = Float(mattePtr[idx]) / 255.0
                let depthVal = Float(depthPtr[idx]) / 255.0
                
                // Background gets blurred, foreground stays sharp
                let blurAmount = (1.0 - matteVal) * (1.0 - depthVal * 0.5)
                let radius = Int(blurAmount * Float(maxBlurRadius))
                
                if radius <= 1 {
                    outPtr[idx] = imgPtr[idx]
                    outPtr[idx + 1] = imgPtr[idx + 1]
                    outPtr[idx + 2] = imgPtr[idx + 2]
                    outPtr[idx + 3] = 255
                    continue
                }
                
                var sumR: Float = 0, sumG: Float = 0, sumB: Float = 0
                var weightSum: Float = 0
                
                // Hexagonal sampling pattern
                for dy in -radius...radius {
                    for dx in -radius...radius {
                        let dist = abs(dx) + abs(dy)
                        if dist > radius * 2 { continue }
                        
                        let ny = y + dy
                        let nx = x + dx
                        guard ny >= 0 && ny < height && nx >= 0 && nx < width else { continue }
                        
                        let nIdx = ny * bytesPerRow + nx * 4
                        
                        // Hexagonal weight (aperture-shaped)
                        let hexWeight = max(0, 1 - Float(dist) / Float(radius))
                        
                        sumR += Float(imgPtr[nIdx]) * hexWeight
                        sumG += Float(imgPtr[nIdx + 1]) * hexWeight
                        sumB += Float(imgPtr[nIdx + 2]) * hexWeight
                        weightSum += hexWeight
                    }
                }
                
                let invW = 1.0 / max(weightSum, 0.001)
                
                // Blend based on matte
                let sharpR = Float(imgPtr[idx])
                let sharpG = Float(imgPtr[idx + 1])
                let sharpB = Float(imgPtr[idx + 2])
                
                let blurR = sumR * invW
                let blurG = sumG * invW
                let blurB = sumB * invW
                
                outPtr[idx] = UInt8(max(0, min(255, sharpR * matteVal + blurR * (1 - matteVal))))
                outPtr[idx + 1] = UInt8(max(0, min(255, sharpG * matteVal + blurG * (1 - matteVal))))
                outPtr[idx + 2] = UInt8(max(0, min(255, sharpB * matteVal + blurB * (1 - matteVal))))
                outPtr[idx + 3] = 255
            }
        }
        
        guard let outProvider = CGDataProvider(data: Data(bytesNoCopy: outData, count: height * bytesPerRow, deallocator: .free) as CFData),
              let outCgImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: outProvider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            free(imageData); free(depthData); free(matteData); free(outData)
            return image
        }
        
        free(imageData); free(depthData); free(matteData)
        return CIImage(cgImage: outCgImage)
    }
}
