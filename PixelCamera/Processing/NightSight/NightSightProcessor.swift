import Foundation
import AVFoundation
import CoreImage
import CoreMotion

actor NightSightProcessor {
    private let motionMeter = MotionMeter.shared
    private let longExposure = LongExposureSimulator.shared
    private let noiseReducer = NoiseReducer.shared
    private let whiteBalancer = AutoWhiteBalancer.shared
    
    func process(photos: [AVCapturePhoto], motionData: [CMDeviceMotion]? = nil) async throws -> CIImage {
        guard photos.count >= 3 else {
            throw CameraError.processingFailed("Need at least 3 frames for Night Sight")
        }
        
        await CameraManager.shared.updateProcessingState(.capturing(frame: photos.count, total: photos.count))
        
        // Step 1: Analyze motion
        let metrics: MotionMeter.MotionMetrics
        if let motions = motionData {
            metrics = motionMeter.analyzeMotionData(motions)
        } else {
            metrics = await motionMeter.measureMotion()
        }
        
        let images = await BurstCaptureManager.shared.collectBurst(photos: photos)
        guard !images.isEmpty else {
            throw CameraError.processingFailed("No images captured")
        }
        
        // Step 2: Long exposure simulation with motion compensation
        await CameraManager.shared.updateProcessingState(.stacking(progress: 0.2))
        let stacked = try await longExposure.simulateLongExposure(images: images, motionData: motionData)
        
        // Step 3: Multi-scale noise reduction
        await CameraManager.shared.updateProcessingState(.denoising(progress: 0.4))
        let denoised = await noiseReducer.reduceNoise(image: stacked, strength: 0.9)
        
        // Step 4: Auto white balance for low light
        await CameraManager.shared.updateProcessingState(.denoising(progress: 0.7))
        let balanced = await whiteBalancer.balance(image: denoised)
        
        // Step 5: Sharpen
        await CameraManager.shared.updateProcessingState(.denoising(progress: 0.9))
        let sharpened = await noiseReducer.sharpen(image: balanced, amount: 0.6)
        
        await CameraManager.shared.updateProcessingState(.finalizing)
        return sharpened
    }
}
