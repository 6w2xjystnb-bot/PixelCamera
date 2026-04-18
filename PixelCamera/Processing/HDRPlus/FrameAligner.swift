import Foundation
import Accelerate
import CoreImage

actor FrameAligner {
    static let shared = FrameAligner()
    
    private let tileSize = 16
    private let searchRadius = 8
    
    struct TileMotion: Equatable {
        let dx: Int
        let dy: Int
        let confidence: Float
    }
    
    struct AlignmentResult {
        let tileMotions: [[TileMotion]]
        let rows: Int
        let cols: Int
    }
    
    func alignFrames(reference: vImage_Buffer, frames: [vImage_Buffer]) -> [AlignmentResult] {
        let width = Int(reference.width)
        let height = Int(reference.height)
        let cols = (width + tileSize - 1) / tileSize
        let rows = (height + tileSize - 1) / tileSize
        
        return frames.map { frame in
            var tileMotions: [[TileMotion]] = []
            
            for row in 0..<rows {
                var rowMotions: [TileMotion] = []
                for col in 0..<cols {
                    let x = col * tileSize
                    let y = row * tileSize
                    let tileW = min(tileSize, width - x)
                    let tileH = min(tileSize, height - y)
                    
                    let motion = findBestMotion(
                        reference: reference,
                        frame: frame,
                        x: x, y: y,
                        width: tileW,
                        height: tileH
                    )
                    rowMotions.append(motion)
                }
                tileMotions.append(rowMotions)
            }
            
            return AlignmentResult(tileMotions: tileMotions, rows: rows, cols: cols)
        }
    }
    
    private func findBestMotion(reference: vImage_Buffer, frame: vImage_Buffer, x: Int, y: Int, width: Int, height: Int) -> TileMotion {
        var bestDx = 0
        var bestDy = 0
        var bestScore = Float.infinity
        
        let refPtr = reference.data.assumingMemoryBound(to: UInt8.self)
        let framePtr = frame.data.assumingMemoryBound(to: UInt8.self)
        let refRowBytes = reference.rowBytes
        let frameRowBytes = frame.rowBytes
        
        for dy in -searchRadius...searchRadius {
            for dx in -searchRadius...searchRadius {
                let score = computeSAD(
                    refPtr: refPtr, refRowBytes: refRowBytes,
                    framePtr: framePtr, frameRowBytes: frameRowBytes,
                    x: x, y: y, dx: dx, dy: dy,
                    width: width, height: height,
                    refWidth: Int(reference.width), refHeight: Int(reference.height),
                    frameWidth: Int(frame.width), frameHeight: Int(frame.height)
                )
                
                if score < bestScore {
                    bestScore = score
                    bestDx = dx
                    bestDy = dy
                }
            }
        }
        
        let confidence = computeConfidence(bestScore: bestScore, reference: reference, x: x, y: y, width: width, height: height)
        return TileMotion(dx: bestDx, dy: bestDy, confidence: confidence)
    }
    
    private func computeSAD(refPtr: UnsafePointer<UInt8>, refRowBytes: Int,
                            framePtr: UnsafePointer<UInt8>, frameRowBytes: Int,
                            x: Int, y: Int, dx: Int, dy: Int,
                            width: Int, height: Int,
                            refWidth: Int, refHeight: Int,
                            frameWidth: Int, frameHeight: Int) -> Float {
        var sad: Float = 0
        var count = 0
        
        for py in 0..<height {
            let refY = y + py
            let frameY = refY + dy
            guard frameY >= 0 && frameY < frameHeight && refY >= 0 && refY < refHeight else { continue }
            
            for px in 0..<width {
                let refX = x + px
                let frameX = refX + dx
                guard frameX >= 0 && frameX < frameWidth && refX >= 0 && refX < refWidth else { continue }
                
                let refIdx = refY * refRowBytes + refX * 4
                let frameIdx = frameY * frameRowBytes + frameX * 4
                
                let rdiff = abs(Int(refPtr[refIdx]) - Int(framePtr[frameIdx]))
                let gdiff = abs(Int(refPtr[refIdx + 1]) - Int(framePtr[frameIdx + 1]))
                let bdiff = abs(Int(refPtr[refIdx + 2]) - Int(framePtr[frameIdx + 2]))
                
                sad += Float(rdiff + gdiff + bdiff) / 3.0
                count += 1
            }
        }
        
        return count > 0 ? sad / Float(count) : Float.infinity
    }
    
    private func computeConfidence(bestScore: Float, reference: vImage_Buffer, x: Int, y: Int, width: Int, height: Int) -> Float {
        var variance: Float = 0
        var mean: Float = 0
        var count = 0
        
        let ptr = reference.data.assumingMemoryBound(to: UInt8.self)
        let rowBytes = reference.rowBytes
        
        for py in 0..<height {
            let pyIdx = (y + py) * rowBytes
            for px in 0..<width {
                let idx = pyIdx + (x + px) * 4
                let lum = Float(ptr[idx]) * 0.299 + Float(ptr[idx + 1]) * 0.587 + Float(ptr[idx + 2]) * 0.114
                mean += lum
                count += 1
            }
        }
        
        mean /= Float(max(count, 1))
        
        for py in 0..<height {
            let pyIdx = (y + py) * rowBytes
            for px in 0..<width {
                let idx = pyIdx + (x + px) * 4
                let lum = Float(ptr[idx]) * 0.299 + Float(ptr[idx + 1]) * 0.587 + Float(ptr[idx + 2]) * 0.114
                variance += (lum - mean) * (lum - mean)
            }
        }
        
        variance /= Float(max(count, 1))
        let normalizedScore = bestScore / max(sqrt(variance), 1.0)
        return max(0, min(1, 1.0 - normalizedScore / 50.0))
    }
    
    func applyAlignment(image: CIImage, alignment: AlignmentResult) -> CIImage {
        // For simplicity, apply a global affine transform based on median motion
        var allDx: [Int] = []
        var allDy: [Int] = []
        
        for row in alignment.tileMotions {
            for motion in row {
                allDx.append(motion.dx)
                allDy.append(motion.dy)
            }
        }
        
        let medianDx = allDx.sorted()[allDx.count / 2]
        let medianDy = allDy.sorted()[allDy.count / 2]
        
        let transform = CGAffineTransform(translationX: CGFloat(-medianDx), y: CGFloat(-medianDy))
        return image.transformed(by: transform)
    }
}
