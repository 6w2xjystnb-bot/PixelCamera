import Foundation
import AVFoundation
import CoreImage
import Accelerate

actor SuperResProcessor {
    private let aligner = SubpixelAligner.shared
    private let reconstructor = DetailReconstructor.shared
    
    func process(photos: [AVCapturePhoto]) async throws -> CIImage {
        guard photos.count >= 4 else {
            throw CameraError.processingFailed("Need at least 4 frames for Super Res")
        }
        
        let images = await BurstCaptureManager.shared.collectBurst(photos: photos)
        guard images.count >= 4 else {
            throw CameraError.processingFailed("Not enough valid images")
        }
        
        await CameraManager.shared.updateProcessingState(.aligning(frame: 1, total: images.count))
        
        let aligned = await aligner.alignSubpixel(images: images)
        
        await CameraManager.shared.updateProcessingState(.merging(progress: 0.5))
        let reconstructed = await reconstructor.reconstruct(images: aligned)
        
        await CameraManager.shared.updateProcessingState(.finalizing)
        return reconstructed
    }
}
