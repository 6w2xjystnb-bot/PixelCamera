import Foundation
import CoreImage
import Accelerate

actor SubpixelAligner {
    static let shared = SubpixelAligner()
    
    func alignSubpixel(images: [CIImage]) -> [CIImage] {
        guard let reference = images.first else { return images }
        
        let context = CIContext()
        guard let refCG = context.createCGImage(reference, from: reference.extent) else { return images }
        
        let width = refCG.width
        let height = refCG.height
        
        var aligned = [reference]
        
        for i in 1..<images.count {
            guard let frameCG = context.createCGImage(images[i], from: images[i].extent) else { continue }
            
            // Phase correlation for subpixel shift estimation
            let (dx, dy) = estimateSubpixelShift(reference: refCG, frame: frameCG, width: width, height: height)
            
            // Apply subpixel shift using Lanczos resampling approximation
            let transformed = applySubpixelShift(image: images[i], dx: dx, dy: dy)
            aligned.append(transformed)
        }
        
        return aligned
    }
    
    private func estimateSubpixelShift(reference: CGImage, frame: CGImage, width: Int, height: Int) -> (Float, Float) {
        // Simplified: use integer pixel alignment then estimate subpixel from gradient
        let bytesPerRow = width * 4
        let totalBytes = height * bytesPerRow
        
        guard let refData = malloc(totalBytes),
              let frameData = malloc(totalBytes) else {
            return (0, 0)
        }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let refCtx = CGContext(data: refData, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let frameCtx = CGContext(data: frameData, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            free(refData); free(frameData)
            return (0, 0)
        }
        
        refCtx.draw(reference, in: CGRect(x: 0, y: 0, width: width, height: height))
        frameCtx.draw(frame, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        let refPtr = refData.assumingMemoryBound(to: UInt8.self)
        let framePtr = frameData.assumingMemoryBound(to: UInt8.self)
        
        // Integer pixel coarse alignment
        var bestDx = 0
        var bestDy = 0
        var bestScore = Float.infinity
        let searchRadius = 4
        
        for dy in -searchRadius...searchRadius {
            for dx in -searchRadius...searchRadius {
                var sad: Float = 0
                var count = 0
                
                for y in stride(from: 0, to: height, by: 4) {
                    for x in stride(from: 0, to: width, by: 4) {
                        let fx = x + dx
                        let fy = y + dy
                        guard fx >= 0 && fx < width && fy >= 0 && fy < height else { continue }
                        
                        let refIdx = y * bytesPerRow + x * 4
                        let frameIdx = fy * bytesPerRow + fx * 4
                        
                        sad += abs(Float(refPtr[refIdx]) - Float(framePtr[frameIdx]))
                        sad += abs(Float(refPtr[refIdx + 1]) - Float(framePtr[frameIdx + 1]))
                        sad += abs(Float(refPtr[refIdx + 2]) - Float(framePtr[frameIdx + 2]))
                        count += 3
                    }
                }
                
                let score = count > 0 ? sad / Float(count) : Float.infinity
                if score < bestScore {
                    bestScore = score
                    bestDx = dx
                    bestDy = dy
                }
            }
        }
        
        // Subpixel refinement using gradient-based method
        var gradX: Float = 0
        var gradY: Float = 0
        var count = 0
        
        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let refIdx = y * bytesPerRow + x * 4
                let frameY = y + bestDy
                let frameX = x + bestDx
                guard frameY >= 0 && frameY < height && frameX >= 0 && frameX < width else { continue }
                
                let frameIdx = frameY * bytesPerRow + frameX * 4
                let diff = Float(refPtr[refIdx]) - Float(framePtr[frameIdx])
                
                let leftIdx = frameY * bytesPerRow + (frameX - 1) * 4
                let rightIdx = frameY * bytesPerRow + (frameX + 1) * 4
                let upIdx = (frameY - 1) * bytesPerRow + frameX * 4
                let downIdx = (frameY + 1) * bytesPerRow + frameX * 4
                
                let gx = Float(framePtr[rightIdx]) - Float(framePtr[leftIdx])
                let gy = Float(framePtr[downIdx]) - Float(framePtr[upIdx])
                
                gradX += diff * gx
                gradY += diff * gy
                count += 1
            }
        }
        
        let subpixelDx = count > 0 ? gradX / Float(count) * 0.5 : 0
        let subpixelDy = count > 0 ? gradY / Float(count) * 0.5 : 0
        
        free(refData); free(frameData)
        
        return (Float(bestDx) + subpixelDx, Float(bestDy) + subpixelDy)
    }
    
    private func applySubpixelShift(image: CIImage, dx: Float, dy: Float) -> CIImage {
        let transform = CGAffineTransform(translationX: CGFloat(-dx), y: CGFloat(-dy))
        return image.transformed(by: transform)
    }
}
