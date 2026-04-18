import Foundation
import CoreImage
import CoreMotion
import Accelerate

actor StarTracker {
    static let shared = StarTracker()
    
    // Compensates for earth rotation using gyroscope data
    // Also performs star alignment between frames
    func trackAndCompensate(images: [CIImage], motionData: [CMDeviceMotion]? = nil) -> [CIImage] {
        guard images.count > 1 else { return images }
        
        var compensated = [images[0]]
        
        for i in 1..<images.count {
            var transform = CGAffineTransform.identity
            
            // Gyro-based compensation for earth rotation
            if let motions = motionData, i < motions.count {
                let current = motions[i]
                let previous = motions[i - 1]
                
                let deltaRoll = current.attitude.roll - previous.attitude.roll
                let deltaPitch = current.attitude.pitch - previous.attitude.pitch
                
                // Compensate for apparent star motion
                // Earth rotates ~15 degrees per hour = 0.004 degrees per second
                // Gyro gives us device rotation, we need to subtract it from star motion
                let compensationX = CGFloat(-deltaRoll * 30)
                let compensationY = CGFloat(-deltaPitch * 30)
                
                transform = transform.translatedBy(x: compensationX, y: compensationY)
            }
            
            // Star-based fine alignment using brightest point tracking
            let fineShift = findStarShift(reference: images[0], frame: images[i])
            transform = transform.translatedBy(x: CGFloat(fineShift.dx), y: CGFloat(fineShift.dy))
            
            let transformed = images[i].transformed(by: transform)
            compensated.append(transformed)
        }
        
        return compensated
    }
    
    private struct StarShift {
        let dx: Float
        let dy: Float
    }
    
    private func findStarShift(reference: CIImage, frame: CIImage) -> StarShift {
        let context = CIContext()
        guard let refCG = context.createCGImage(reference, from: reference.extent),
              let frameCG = context.createCGImage(frame, from: frame.extent) else {
            return StarShift(dx: 0, dy: 0)
        }
        
        let width = refCG.width
        let height = refCG.height
        let bytesPerRow = width * 4
        let totalBytes = height * bytesPerRow
        
        guard let refData = malloc(totalBytes),
              let frameData = malloc(totalBytes) else {
            return StarShift(dx: 0, dy: 0)
        }
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let refCtx = CGContext(data: refData, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let frameCtx = CGContext(data: frameData, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            free(refData); free(frameData)
            return StarShift(dx: 0, dy: 0)
        }
        
        refCtx.draw(refCG, in: CGRect(x: 0, y: 0, width: width, height: height))
        frameCtx.draw(frameCG, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        let refPtr = refData.assumingMemoryBound(to: UInt8.self)
        let framePtr = frameData.assumingMemoryBound(to: UInt8.self)
        
        // Find brightest regions (stars) in downsampled image
        let scale = 8
        let smallW = width / scale
        let smallH = height / scale
        
        var refStars: [(Int, Int, Float)] = []
        var frameStars: [(Int, Int, Float)] = []
        
        for y in 0..<smallH {
            for x in 0..<smallW {
                let origX = x * scale
                let origY = y * scale
                
                var refSum: Float = 0
                var frameSum: Float = 0
                
                for dy in 0..<scale {
                    for dx in 0..<scale {
                        let idx = (origY + dy) * bytesPerRow + (origX + dx) * 4
                        refSum += Float(refPtr[idx]) + Float(refPtr[idx + 1]) + Float(refPtr[idx + 2])
                        frameSum += Float(framePtr[idx]) + Float(framePtr[idx + 1]) + Float(framePtr[idx + 2])
                    }
                }
                
                refStars.append((x, y, refSum))
                frameStars.append((x, y, frameSum))
            }
        }
        
        // Find top brightest regions
        let topRef = refStars.sorted { $0.2 > $1.2 }.prefix(5)
        let topFrame = frameStars.sorted { $0.2 > $1.2 }.prefix(5)
        
        var dx: Float = 0
        var dy: Float = 0
        var count = 0
        
        // Match stars and compute median shift
        for refStar in topRef {
            let closest = topFrame.min { a, b in
                let distA = abs(a.0 - refStar.0) + abs(a.1 - refStar.1)
                let distB = abs(b.0 - refStar.0) + abs(b.1 - refStar.1)
                return distA < distB
            }
            
            if let closest = closest {
                dx += Float(closest.0 - refStar.0) * Float(scale)
                dy += Float(closest.1 - refStar.1) * Float(scale)
                count += 1
            }
        }
        
        free(refData); free(frameData)
        
        if count > 0 {
            return StarShift(dx: dx / Float(count), dy: dy / Float(count))
        }
        
        return StarShift(dx: 0, dy: 0)
    }
}
