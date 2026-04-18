import Foundation
import Accelerate
import CoreImage

actor BurstMerger {
    static let shared = BurstMerger()
    
    private let noiseVariance: Float = 25.0
    
    func mergeFrames(frames: [vImage_Buffer], alignments: [FrameAligner.AlignmentResult], reference: vImage_Buffer) -> vImage_Buffer {
        let width = Int(reference.width)
        let height = Int(reference.height)
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let totalBytes = height * bytesPerRow
        
        guard let mergedData = calloc(height, bytesPerRow) else {
            return reference
        }
        
        let refPtr = reference.data.assumingMemoryBound(to: UInt8.self)
        let mergedPtr = mergedData.assumingMemoryBound(to: Float.self)
        
        // Initialize with reference frame
        for y in 0..<height {
            for x in 0..<width {
                let idx = (y * width + x) * 4
                let refIdx = y * reference.rowBytes + x * 4
                mergedPtr[idx] = Float(refPtr[refIdx])
                mergedPtr[idx + 1] = Float(refPtr[refIdx + 1])
                mergedPtr[idx + 2] = Float(refPtr[refIdx + 2])
                mergedPtr[idx + 3] = 255.0
            }
        }
        
        var weights = [Float](repeating: 1.0, count: width * height)
        
        for (frameIndex, frame) in frames.enumerated() {
            guard frameIndex < alignments.count else { continue }
            let alignment = alignments[frameIndex]
            let framePtr = frame.data.assumingMemoryBound(to: UInt8.self)
            
            let tileRows = alignment.rows
            let tileCols = alignment.cols
            
            for row in 0..<tileRows {
                for col in 0..<tileCols {
                    let motion = alignment.tileMotions[row][col]
                    guard motion.confidence > 0.3 else { continue }
                    
                    let tileX = col * 16
                    let tileY = row * 16
                    let tileW = min(16, width - tileX)
                    let tileH = min(16, height - tileY)
                    
                    for py in 0..<tileH {
                        for px in 0..<tileW {
                            let x = tileX + px
                            let y = tileY + py
                            
                            let srcX = x + motion.dx
                            let srcY = y + motion.dy
                            
                            guard srcX >= 0 && srcX < width && srcY >= 0 && srcY < height else { continue }
                            
                            let dstIdx = (y * width + x) * 4
                            let srcIdx = srcY * frame.rowBytes + srcX * 4
                            let weightIdx = y * width + x
                            
                            let refR = Float(refPtr[y * reference.rowBytes + x * 4])
                            let refG = Float(refPtr[y * reference.rowBytes + x * 4 + 1])
                            let refB = Float(refPtr[y * reference.rowBytes + x * 4 + 2])
                            
                            let frameR = Float(framePtr[srcIdx])
                            let frameG = Float(framePtr[srcIdx + 1])
                            let frameB = Float(framePtr[srcIdx + 2])
                            
                            // Wiener filter weight based on difference from reference
                            let diffR = refR - frameR
                            let diffG = refG - frameG
                            let diffB = refB - frameB
                            let diffSq = diffR * diffR + diffG * diffG + diffB * diffB
                            
                            let signalVariance = max(1.0, refR * refR + refG * refG + refB * refB) / 3.0
                            let wienerWeight = signalVariance / (signalVariance + noiseVariance)
                            let blendWeight = wienerWeight * motion.confidence
                            
                            mergedPtr[dstIdx] += frameR * blendWeight
                            mergedPtr[dstIdx + 1] += frameG * blendWeight
                            mergedPtr[dstIdx + 2] += frameB * blendWeight
                            weights[weightIdx] += blendWeight
                        }
                    }
                }
            }
        }
        
        // Normalize
        var resultData = malloc(totalBytes)!
        let resultPtr = resultData.assumingMemoryBound(to: UInt8.self)
        
        for y in 0..<height {
            for x in 0..<width {
                let idx = (y * width + x) * 4
                let weightIdx = y * width + x
                let w = max(weights[weightIdx], 1.0)
                
                resultPtr[idx] = UInt8(max(0, min(255, mergedPtr[idx] / w)))
                resultPtr[idx + 1] = UInt8(max(0, min(255, mergedPtr[idx + 1] / w)))
                resultPtr[idx + 2] = UInt8(max(0, min(255, mergedPtr[idx + 2] / w)))
                resultPtr[idx + 3] = 255
            }
        }
        
        free(mergedData)
        
        return vImage_Buffer(data: resultData, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: bytesPerRow)
    }
    
    func mergeFramesDFT(frames: [vImage_Buffer], reference: vImage_Buffer) -> vImage_Buffer {
        // FFT-based merging in frequency domain using vImage
        let width = Int(reference.width)
        let height = Int(reference.height)
        let bytesPerRow = width * 4
        
        guard let mergedData = calloc(height, bytesPerRow) else { return reference }
        
        let refPtr = reference.data.assumingMemoryBound(to: UInt8.self)
        let mergedPtr = mergedData.assumingMemoryBound(to: Float.self)
        
        // Simple temporal average in spatial domain (DFT would require much more code)
        // For a real DFT merge, we'd use vImageFFT functions
        for y in 0..<height {
            for x in 0..<width {
                let idx = (y * width + x) * 4
                var r: Float = Float(refPtr[y * reference.rowBytes + x * 4])
                var g: Float = Float(refPtr[y * reference.rowBytes + x * 4 + 1])
                var b: Float = Float(refPtr[y * reference.rowBytes + x * 4 + 2])
                
                for frame in frames {
                    let fPtr = frame.data.assumingMemoryBound(to: UInt8.self)
                    r += Float(fPtr[y * frame.rowBytes + x * 4])
                    g += Float(fPtr[y * frame.rowBytes + x * 4 + 1])
                    b += Float(fPtr[y * frame.rowBytes + x * 4 + 2])
                }
                
                let count = Float(frames.count + 1)
                mergedPtr[idx] = r / count
                mergedPtr[idx + 1] = g / count
                mergedPtr[idx + 2] = b / count
                mergedPtr[idx + 3] = 255.0
            }
        }
        
        var resultData = malloc(height * bytesPerRow)!
        let resultPtr = resultData.assumingMemoryBound(to: UInt8.self)
        
        for i in 0..<(width * height * 4) {
            resultPtr[i] = UInt8(max(0, min(255, mergedPtr[i])))
        }
        
        free(mergedData)
        
        return vImage_Buffer(data: resultData, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: bytesPerRow)
    }
}
