import Foundation
import CoreVideo
import CoreImage
import Accelerate

extension CVPixelBuffer {
    var width: Int { CVPixelBufferGetWidth(self) }
    var height: Int { CVPixelBufferGetHeight(self) }
    var bytesPerRow: Int { CVPixelBufferGetBytesPerRow(self) }
    var pixelFormatType: OSType { CVPixelBufferGetPixelFormatType(self) }
    
    func lockBaseAddress(_ flags: CVPixelBufferLockFlags = .readOnly) {
        CVPixelBufferLockBaseAddress(self, flags)
    }
    
    func unlockBaseAddress(_ flags: CVPixelBufferLockFlags = .readOnly) {
        CVPixelBufferUnlockBaseAddress(self, flags)
    }
    
    var baseAddress: UnsafeMutableRawPointer? {
        CVPixelBufferGetBaseAddress(self)
    }
    
    func toCIImage() -> CIImage {
        return CIImage(cvPixelBuffer: self)
    }
    
    func toGrayscale() -> CVPixelBuffer? {
        let width = self.width
        let height = self.height
        
        var grayBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_OneComponent8, attrs as CFDictionary, &grayBuffer)
        guard let output = grayBuffer else { return nil }
        
        lockBaseAddress()
        defer { unlockBaseAddress() }
        output.lockBaseAddress()
        defer { output.unlockBaseAddress() }
        
        guard let src = baseAddress, let dst = output.baseAddress else { return nil }
        
        var srcBuffer = vImage_Buffer(data: src, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: bytesPerRow)
        var dstBuffer = vImage_Buffer(data: dst, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: CVPixelBufferGetBytesPerRow(output))
        
        let matrix: [Int16] = [
            54, 183, 19, 0
        ]
        
        vImageMatrixMultiply_ARGB8888ToPlanar8(&srcBuffer, &dstBuffer, matrix, 8, nil, 0, vImage_Flags(kvImageNoFlags))
        
        return output
    }
    
    func copy() -> CVPixelBuffer? {
        let width = self.width
        let height = self.height
        let format = pixelFormatType
        
        var newBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, format, attrs as CFDictionary, &newBuffer)
        guard let output = newBuffer else { return nil }
        
        lockBaseAddress()
        defer { unlockBaseAddress() }
        output.lockBaseAddress()
        defer { output.unlockBaseAddress() }
        
        guard let src = baseAddress, let dst = output.baseAddress else { return nil }
        memcpy(dst, src, height * bytesPerRow)
        
        return output
    }
    
    static func create(width: Int, height: Int, pixelFormat: OSType = kCVPixelFormatType_32BGRA) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, pixelFormat, attrs as CFDictionary, &pixelBuffer)
        return pixelBuffer
    }
}

extension CIImage {
    func toPixelBuffer() -> CVPixelBuffer? {
        let extent = self.extent
        guard let pixelBuffer = CVPixelBuffer.create(width: Int(extent.width), height: Int(extent.height)) else {
            return nil
        }
        
        let context = CIContext()
        context.render(self, to: pixelBuffer)
        return pixelBuffer
    }
    
    func normalized() -> CIImage {
        return self.applyingFilter("CIColorMatrix", parameters: [
            kCIInputImageKey: self,
            "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)
        ])
    }
    
    func gammaAdjusted(_ gamma: Float) -> CIImage {
        return self.applyingFilter("CIGammaAdjust", parameters: [
            kCIInputImageKey: self,
            "inputPower": gamma
        ])
    }
    
    func exposureAdjusted(_ ev: Float) -> CIImage {
        return self.applyingFilter("CIExposureAdjust", parameters: [
            kCIInputImageKey: self,
            "inputEV": ev
        ])
    }
}

extension vImage_Buffer {
    mutating func toCIImage(width: Int, height: Int, bitsPerComponent: Int = 8) -> CIImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let data = data else { return nil }
        
        guard let provider = CGDataProvider(data: Data(bytes: data, count: Int(rowBytes * height)) as CFData) else {
            return nil
        }
        
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bitsPerPixel: bitsPerComponent * 4,
            bytesPerRow: Int(rowBytes),
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            return nil
        }
        
        return CIImage(cgImage: cgImage)
    }
}
