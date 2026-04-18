import Foundation
import CoreImage
import Accelerate

actor DepthEstimator {
    static let shared = DepthEstimator()
    
    // Fallback depth estimation when AVDepthData is not available
    // Uses a simplified depth-from-defocus approach
    func estimateDepth(image: CIImage) -> CIImage {
        // Use edge magnitude as proxy for depth (simplification)
        // In a real implementation, this would use a CoreML depth model
        let edges = image.applyingFilter("CIEdges", parameters: ["inputIntensity": 1.0])
        let grayscale = edges.applyingFilter("CIPhotoEffectMono")
        
        // Invert: closer objects have stronger edges in portrait mode (typically)
        let inverted = grayscale.applyingFilter("CIColorInvert")
        
        // Blur to create smooth depth map
        let blurred = inverted.applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 10])
        
        return blurred
    }
    
    func depthFromDualCameras(leftImage: CIImage, rightImage: CIImage) -> CIImage {
        // Simplified stereo matching using block matching
        // Real implementation would use dense stereo correspondence
        let diff = leftImage.applyingFilter("CIDifferenceBlendMode", parameters: [kCIInputBackgroundImageKey: rightImage])
        let grayscale = diff.applyingFilter("CIPhotoEffectMono")
        let blurred = grayscale.applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 5])
        return blurred
    }
}
