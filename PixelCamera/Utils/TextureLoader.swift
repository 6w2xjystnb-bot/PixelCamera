import Foundation
import Metal
import MetalKit
import CoreImage
import CoreVideo

final class TextureLoader {
    static let shared = TextureLoader()
    private let context = MetalContext.shared
    
    func texture(from pixelBuffer: CVPixelBuffer, pixelFormat: MTLPixelFormat = .bgra8Unorm) -> MTLTexture? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        var cvTexture: CVMetalTexture?
        let textureCache = TextureCache.shared.cache
        
        let result = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            pixelFormat,
            width,
            height,
            0,
            &cvTexture
        )
        
        guard result == kCVReturnSuccess, let cvTexture = cvTexture else {
            return nil
        }
        
        return CVMetalTextureGetTexture(cvTexture)
    }
    
    func texture(from ciImage: CIImage, context: CIContext? = nil) -> MTLTexture? {
        let extent = ciImage.extent
        guard let cgImage = (context ?? CIContext()).createCGImage(ciImage, from: extent) else {
            return nil
        }
        return texture(from: cgImage)
    }
    
    func texture(from cgImage: CGImage) -> MTLTexture? {
        guard let context = MetalContext.shared else { return nil }
        do {
            return try context.textureLoader.newTexture(cgImage: cgImage, options: nil)
        } catch {
            print("Failed to load texture from CGImage: \(error)")
            return nil
        }
    }
    
    func texture(from data: Data, width: Int, height: Int, pixelFormat: MTLPixelFormat = .rgba8Unorm) -> MTLTexture? {
        guard let context = MetalContext.shared,
              let texture = context.makeTexture(width: width, height: height, pixelFormat: pixelFormat, usage: [.shaderRead, .shaderWrite]) else {
            return nil
        }
        
        let region = MTLRegionMake2D(0, 0, width, height)
        data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            texture.replace(region: region, mipmapLevel: 0, withBytes: baseAddress, bytesPerRow: width * 4)
        }
        return texture
    }
    
    func pixelBuffer(from texture: MTLTexture, pixelFormat: OSType = kCVPixelFormatType_32BGRA) -> CVPixelBuffer? {
        let width = texture.width
        let height = texture.height
        
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            pixelFormat,
            attributes as CFDictionary,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }
        
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        
        let region = MTLRegionMake2D(0, 0, width, height)
        texture.getBytes(baseAddress, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)
        
        return buffer
    }
    
    func ciImage(from texture: MTLTexture) -> CIImage? {
        guard let pixelBuffer = pixelBuffer(from: texture) else { return nil }
        return CIImage(cvPixelBuffer: pixelBuffer)
    }
}

final class TextureCache {
    static let shared = TextureCache()
    let cache: CVMetalTextureCache
    
    private init() {
        var cacheRef: CVMetalTextureCache?
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal not available")
        }
        let result = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cacheRef)
        guard result == kCVReturnSuccess, let cache = cacheRef else {
            fatalError("Failed to create texture cache")
        }
        self.cache = cache
    }
}
