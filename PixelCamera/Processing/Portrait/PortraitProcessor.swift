import Foundation
import AVFoundation
import CoreImage

actor PortraitProcessor {
    private let depthEstimator = DepthEstimator.shared
    private let matteGenerator = MatteGenerator.shared
    private let bokehRenderer = BokehRenderer.shared
    private let hairRefiner = HairRefiner.shared
    
    func process(photos: [AVCapturePhoto]) async throws -> CIImage {
        guard let photo = photos.first else {
            throw CameraError.processingFailed("No photo for portrait mode")
        }
        
        await CameraManager.shared.updateProcessingState(.depthProcessing(progress: 0.1))
        
        let image: CIImage
        if let pixelBuffer = photo.pixelBuffer {
            image = CIImage(cvPixelBuffer: pixelBuffer)
        } else if let data = photo.fileDataRepresentation(),
                  let uiImage = UIImage(data: data),
                  let cgImage = uiImage.cgImage {
            image = CIImage(cgImage: cgImage)
        } else {
            throw CameraError.processingFailed("Failed to get image")
        }
        
        // Step 1: Get depth data
        let depthData: CIImage
        if let avDepth = photo.depthData {
            depthData = CIImage(cvPixelBuffer: avDepth.depthDataMap)
        } else {
            depthData = await depthEstimator.estimateDepth(image: image)
        }
        
        // Step 2: Generate refined matte
        await CameraManager.shared.updateProcessingState(.depthProcessing(progress: 0.4))
        let matte = await matteGenerator.generateMatte(from: depthData, image: image)
        
        // Step 3: Render bokeh
        await CameraManager.shared.updateProcessingState(.bokehRendering(progress: 0.5))
        let bokehImage = await bokehRenderer.renderBokeh(image: image, depth: depthData, matte: matte)
        
        // Step 4: Refine edges
        await CameraManager.shared.updateProcessingState(.bokehRendering(progress: 0.8))
        let refined = await hairRefiner.refine(image: bokehImage, matte: matte, original: image)
        
        await CameraManager.shared.updateProcessingState(.finalizing)
        return refined
    }
}
