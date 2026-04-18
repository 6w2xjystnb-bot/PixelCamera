import Foundation
import CoreImage
import Accelerate

actor DetailReconstructor {
    static let shared = DetailReconstructor()
    
    func reconstruct(images: [CIImage]) -> CIImage {
        guard let reference = images.first else { return CIImage() }
        
        let context = CIContext()
        guard let refCG = context.createCGImage(reference, from: reference.extent) else { return reference }
        
        let width = refCG.width
        let height = refCG.height
        let bytesPerRow = width * 4
        let totalBytes = height * bytesPerRow
        
        // Convert all images to buffers
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
        let outPtr = outData.assumingMemoryBound(to: UInt8.self)
        
        // Frequency-based detail reconstruction
        // Combine low frequencies from temporal average with high frequencies from sharpest frame
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * bytesPerRow + x * 4
                
                // Temporal average (low frequency)
                var avgR: Float = 0, avgG: Float = 0, avgB: Float = 0
                for buffer in buffers {
                    avgR += Float(buffer[idx])
                    avgG += Float(buffer[idx + 1])
                    avgB += Float(buffer[idx + 2])
                }
                avgR /= Float(buffers.count)
                avgG /= Float(buffers.count)
                avgB /= Float(buffers.count)
                
                // Find sharpest local frame using variance
                var bestVar: Float = 0
                var bestR: Float = 0, bestG: Float = 0, bestB: Float = 0
                
                for buffer in buffers {
                    // Local variance (simple 3x3)
                    var varR: Float = 0, varG: Float = 0, varB: Float = 0
                    var count = 0
                    
                    for dy in -1...1 {
                        for dx in -1...1 {
                            let ny = y + dy
                            let nx = x + dx
                            guard ny >= 0 && ny < height && nx >= 0 && nx < width else { continue }
                            let nIdx = ny * bytesPerRow + nx * 4
                            let diffR = Float(buffer[nIdx]) - avgR
                            let diffG = Float(buffer[nIdx + 1]) - avgG
                            let diffB = Float(buffer[nIdx + 2]) - avgB
                            varR += diffR * diffR
                            varG += diffG * diffG
                            varB += diffB * diffB
                            count += 1
                        }
                    }
                    
                    let totalVar = (varR + varG + varB) / Float(max(count, 1))
                    if totalVar > bestVar {
                        bestVar = totalVar
                        bestR = Float(buffer[idx])
                        bestG = Float(buffer[idx + 1])
                        bestB = Float(buffer[idx + 2])
                    }
                }
                
                // Blend: low freq from average, high freq from sharpest
                let lowPassRatio: Float = 0.6
                let highPassRatio: Float = 0.4
                
                let detailR = bestR - avgR
                let detailG = bestG - avgG
                let detailB = bestB - avgB
                
                let finalR = avgR + detailR * highPassRatio / lowPassRatio
                let finalG = avgG + detailG * highPassRatio / lowPassRatio
                let finalB = avgB + detailB * highPassRatio / lowPassRatio
                
                outPtr[idx] = UInt8(max(0, min(255, finalR)))
                outPtr[idx + 1] = UInt8(max(0, min(255, finalG)))
                outPtr[idx + 2] = UInt8(max(0, min(255, finalB)))
                outPtr[idx + 3] = 255
            }
        }
        
        for buffer in buffers {
            free(buffer)
        }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let outProvider = CGDataProvider(data: Data(bytesNoCopy: outData, count: totalBytes, deallocator: .free) as CFData),
              let outCgImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: outProvider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            free(outData)
            return reference
        }
        
        return CIImage(cgImage: outCgImage)
    }
}
