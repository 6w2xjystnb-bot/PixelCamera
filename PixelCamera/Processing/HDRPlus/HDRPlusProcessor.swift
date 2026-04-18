import Foundation
import AVFoundation
import CoreImage
import CoreVideo
import Accelerate

actor HDRPlusProcessor {
    private let burstManager = BurstCaptureManager.shared
    private let aligner = FrameAligner.shared
    private let merger = BurstMerger.shared
    private let toneMapper = ToneMapper.shared
    private let dehazer = Dehazer.shared
    private let colorTuner = ColorTuner.shared
    
    func process(photos: [AVCapturePhoto]) async throws -> CIImage {
        guard photos.count >= 3 else {
            throw CameraError.processingFailed("Need at least 3 frames for HDR+")
        }
        
        await CameraManager.shared.updateProcessingState(.aligning(frame: 0, total: photos.count))
        
        let images = await burstManager.collectBurst(photos: photos)
        guard let referenceImage = images.first else {
            throw CameraError.processingFailed("No reference image")
        }
        
        // Convert to buffers
        let buffers = await burstManager.convertToGrayscaleBuffers(images: images)
        guard let referenceBuffer = buffers.first else {
            throw CameraError.processingFailed("Failed to create reference buffer")
        }
        
        let alignmentFrames = Array(buffers.dropFirst())
        
        // Step 1: Tile-based alignment
        await CameraManager.shared.updateProcessingState(.aligning(frame: 1, total: photos.count))
        let alignments = await aligner.alignFrames(reference: referenceBuffer, frames: alignmentFrames)
        
        // Step 2: Merge with Wiener filtering
        await CameraManager.shared.updateProcessingState(.merging(progress: 0.3))
        let mergedBuffer = await merger.mergeFrames(frames: alignmentFrames, alignments: alignments, reference: referenceBuffer)
        
        // Convert merged buffer back to CIImage
        let mergedImage = bufferToCIImage(buffer: mergedBuffer, width: Int(referenceBuffer.width), height: Int(referenceBuffer.height))
        
        burstManager.freeBuffers(buffers)
        burstManager.freeBuffers([mergedBuffer])
        
        // Step 3: Tone mapping
        await CameraManager.shared.updateProcessingState(.toneMapping(progress: 0.5))
        let toneMapped = await toneMapper.toneMap(image: mergedImage)
        
        // Step 4: Dehaze / veiling glare removal
        await CameraManager.shared.updateProcessingState(.toneMapping(progress: 0.7))
        let dehazed = await dehazer.dehaze(image: toneMapped)
        let glareRemoved = await dehazer.removeVeilingGlare(image: dehazed)
        
        // Step 5: Color tuning
        await CameraManager.shared.updateProcessingState(.toneMapping(progress: 0.9))
        let finalImage = await colorTuner.tune(image: glareRemoved)
        
        await CameraManager.shared.updateProcessingState(.finalizing)
        return finalImage
    }
    
    private func bufferToCIImage(buffer: vImage_Buffer, width: Int, height: Int) -> CIImage {
        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        guard let provider = CGDataProvider(data: Data(bytesNoCopy: buffer.data, count: height * bytesPerRow, deallocator: .none) as CFData),
              let cgImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            return CIImage()
        }
        
        return CIImage(cgImage: cgImage)
    }
}
