import Foundation
import AVFoundation
import CoreImage
import CoreMotion

actor AstroProcessor {
    private let starTracker = StarTracker.shared
    private let darkFrameSubtractor = DarkFrameSubtractor.shared
    private let starStacker = StarStacker.shared
    
    func process(photos: [AVCapturePhoto], motionData: [CMDeviceMotion]? = nil) async throws -> CIImage {
        guard photos.count >= 10 else {
            throw CameraError.processingFailed("Need at least 10 frames for Astro mode")
        }
        
        await CameraManager.shared.updateProcessingState(.capturing(frame: photos.count, total: photos.count))
        
        let images = await BurstCaptureManager.shared.collectBurst(photos: photos)
        guard images.count >= 10 else {
            throw CameraError.processingFailed("Not enough valid frames")
        }
        
        // Step 1: Track stars and compensate for earth rotation
        await CameraManager.shared.updateProcessingState(.starTracking(progress: 0.1))
        let trackedImages = await starTracker.trackAndCompensate(images: images, motionData: motionData)
        
        // Step 2: Dark frame subtraction (hot pixel removal)
        await CameraManager.shared.updateProcessingState(.starTracking(progress: 0.3))
        let cleanedImages = await darkFrameSubtractor.subtractDarkFrames(images: trackedImages)
        
        // Step 3: Star stacking with foreground preservation
        await CameraManager.shared.updateProcessingState(.stacking(progress: 0.5))
        let stacked = await starStacker.stackStars(images: cleanedImages)
        
        // Step 4: Final tone mapping for night sky
        await CameraManager.shared.updateProcessingState(.stacking(progress: 0.9))
        let toneMapped = stacked.applyingFilter("CIExposureAdjust", parameters: ["inputEV": 1.5])
            .applyingFilter("CIGammaAdjust", parameters: ["inputPower": 0.7])
            .applyingFilter("CIVibrance", parameters: ["inputAmount": 0.3])
        
        await CameraManager.shared.updateProcessingState(.finalizing)
        return toneMapped
    }
}
