import Foundation
import AVFoundation
import CoreImage
import CoreVideo

actor BurstCaptureManager {
    static let shared = BurstCaptureManager()
    
    private var burstFrames: [CVPixelBuffer] = []
    private let maxFrames = 15
    
    func collectBurst(photos: [AVCapturePhoto]) async throws -> [CIImage] {
        var images: [CIImage] = []
        
        for photo in photos {
            if let pixelBuffer = photo.pixelBuffer {
                images.append(CIImage(cvPixelBuffer: pixelBuffer))
            } else if let data = photo.fileDataRepresentation(),
                      let uiImage = UIImage(data: data),
                      let cgImage = uiImage.cgImage {
                images.append(CIImage(cgImage: cgImage))
            }
        }
        
        return images
    }
    
    func convertToGrayscaleBuffers(images: [CIImage]) -> [vImage_Buffer] {
        let context = CIContext()
        var buffers: [vImage_Buffer] = []
        
        for image in images {
            guard let cgImage = context.createCGImage(image, from: image.extent) else { continue }
            let width = cgImage.width
            let height = cgImage.height
            
            let bytesPerPixel = 4
            let bytesPerRow = width * bytesPerPixel
            let totalBytes = height * bytesPerRow
            
            guard let data = malloc(totalBytes) else { continue }
            
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let bitmapContext = CGContext(
                    data: data,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: bytesPerRow,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                free(data)
                continue
            }
            
            bitmapContext.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            
            let buffer = vImage_Buffer(data: data, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: bytesPerRow)
            buffers.append(buffer)
        }
        
        return buffers
    }
    
    func normalizeBuffers(_ buffers: [vImage_Buffer]) -> [vImage_Buffer] {
        // For 8-bit images, values are already in [0, 255] range
        // Return copies to ensure independent buffers
        return buffers.map { buffer in
            let size = Int(buffer.height * buffer.rowBytes)
            let newData = malloc(size)!
            memcpy(newData, buffer.data, size)
            return vImage_Buffer(data: newData, height: buffer.height, width: buffer.width, rowBytes: buffer.rowBytes)
        }
    }
    
    func freeBuffers(_ buffers: [vImage_Buffer]) {
        for buffer in buffers {
            free(buffer.data)
        }
    }
    
    func extractYChannel(from buffer: vImage_Buffer, width: Int, height: Int) -> vImage_Buffer {
        let grayRowBytes = width
        let grayData = malloc(height * grayRowBytes)
        var grayBuffer = vImage_Buffer(data: grayData, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: grayRowBytes)
        
        var source = buffer
        let matrix: [Int16] = [54, 183, 19, 0]
        vImageMatrixMultiply_ARGB8888ToPlanar8(&source, &grayBuffer, matrix, 8, nil, vImage_Flags(kvImageNoFlags))
        
        return grayBuffer
    }
}
