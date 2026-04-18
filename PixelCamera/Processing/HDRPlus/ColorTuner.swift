import Foundation
import CoreImage
import Accelerate

actor ColorTuner {
    static let shared = ColorTuner()
    
    func tune(image: CIImage) -> CIImage {
        var result = image
        
        // Shift cyans toward blue
        result = shiftHue(image: result, fromHue: 0.45...0.55, toHue: 0.55...0.65, shift: 0.08)
        
        // Boost blue and green saturation
        result = boostSaturation(image: result, hueRange: 0.55...0.75, boost: 1.25)
        result = boostSaturation(image: result, hueRange: 0.25...0.45, boost: 1.15)
        
        // Slightly warm shadows
        result = warmShadows(image: result, warmth: 0.03)
        
        // Increase overall vibrance slightly
        result = result.applyingFilter("CIVibrance", parameters: ["inputAmount": 0.15])
        
        return result
    }
    
    private func shiftHue(image: CIImage, fromHue: ClosedRange<Float>, toHue: ClosedRange<Float>, shift: Float) -> CIImage {
        guard let cgImage = CIContext().createCGImage(image, from: image.extent) else { return image }
        
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        let totalBytes = height * bytesPerRow
        
        guard let data = malloc(totalBytes) else { return image }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            free(data)
            return image
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let ptr = data.assumingMemoryBound(to: UInt8.self)
        
        let outData = malloc(totalBytes)!
        let outPtr = outData.assumingMemoryBound(to: UInt8.self)
        
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * bytesPerRow + x * 4
                let r = Float(ptr[idx]) / 255.0
                let g = Float(ptr[idx + 1]) / 255.0
                let b = Float(ptr[idx + 2]) / 255.0
                
                let (h, s, v) = rgbToHsv(r: r, g: g, b: b)
                
                var newH = h
                if fromHue.contains(Float(h)) {
                    let t = (Float(h) - fromHue.lowerBound) / (fromHue.upperBound - fromHue.lowerBound)
                    newH = Double(fromHue.lowerBound + shift * t + (toHue.lowerBound - fromHue.lowerBound) * t)
                    newH = newH.truncatingRemainder(dividingBy: 1.0)
                }
                
                let (nr, ng, nb) = hsvToRgb(h: newH, s: s, v: v)
                
                outPtr[idx] = UInt8(max(0, min(255, nr * 255)))
                outPtr[idx + 1] = UInt8(max(0, min(255, ng * 255)))
                outPtr[idx + 2] = UInt8(max(0, min(255, nb * 255)))
                outPtr[idx + 3] = 255
            }
        }
        
        guard let outProvider = CGDataProvider(data: Data(bytesNoCopy: outData, count: totalBytes, deallocator: .free) as CFData),
              let outCgImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: outProvider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            free(data)
            free(outData)
            return image
        }
        
        free(data)
        return CIImage(cgImage: outCgImage)
    }
    
    private func boostSaturation(image: CIImage, hueRange: ClosedRange<Float>, boost: Float) -> CIImage {
        guard let cgImage = CIContext().createCGImage(image, from: image.extent) else { return image }
        
        let width = cgImage.width
        let height = cgImage.height
        let bytesPerRow = width * 4
        let totalBytes = height * bytesPerRow
        
        guard let data = malloc(totalBytes) else { return image }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            free(data)
            return image
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let ptr = data.assumingMemoryBound(to: UInt8.self)
        
        let outData = malloc(totalBytes)!
        let outPtr = outData.assumingMemoryBound(to: UInt8.self)
        
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * bytesPerRow + x * 4
                let r = Float(ptr[idx]) / 255.0
                let g = Float(ptr[idx + 1]) / 255.0
                let b = Float(ptr[idx + 2]) / 255.0
                
                let (h, s, v) = rgbToHsv(r: r, g: g, b: b)
                
                var newS = s
                if hueRange.contains(Float(h)) {
                    newS = min(1.0, s * Double(boost))
                }
                
                let (nr, ng, nb) = hsvToRgb(h: h, s: newS, v: v)
                
                outPtr[idx] = UInt8(max(0, min(255, nr * 255)))
                outPtr[idx + 1] = UInt8(max(0, min(255, ng * 255)))
                outPtr[idx + 2] = UInt8(max(0, min(255, nb * 255)))
                outPtr[idx + 3] = 255
            }
        }
        
        guard let outProvider = CGDataProvider(data: Data(bytesNoCopy: outData, count: totalBytes, deallocator: .free) as CFData),
              let outCgImage = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: outProvider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            free(data)
            free(outData)
            return image
        }
        
        free(data)
        return CIImage(cgImage: outCgImage)
    }
    
    private func warmShadows(image: CIImage, warmth: Float) -> CIImage {
        let matrix = CIFilter(name: "CIColorMatrix", parameters: [
            kCIInputImageKey: image,
            "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: CGFloat(warmth * 5), y: CGFloat(warmth * 2), z: CGFloat(-warmth * 3), w: 0)
        ])
        return matrix?.outputImage ?? image
    }
    
    private func rgbToHsv(r: Float, g: Float, b: Float) -> (h: Double, s: Double, v: Double) {
        let maxVal = max(r, max(g, b))
        let minVal = min(r, min(g, b))
        let diff = maxVal - minVal
        
        var h: Float = 0
        if diff != 0 {
            if maxVal == r {
                h = 60 * ((g - b) / diff)
            } else if maxVal == g {
                h = 60 * (2 + (b - r) / diff)
            } else {
                h = 60 * (4 + (r - g) / diff)
            }
        }
        if h < 0 { h += 360 }
        
        let s = maxVal == 0 ? 0 : diff / maxVal
        return (Double(h / 360.0), Double(s), Double(maxVal))
    }
    
    private func hsvToRgb(h: Double, s: Double, v: Double) -> (r: Float, g: Float, b: Float) {
        let c = v * s
        let x = c * (1 - abs((h * 6).truncatingRemainder(dividingBy: 2) - 1))
        let m = v - c
        
        var r: Double = 0, g: Double = 0, b: Double = 0
        let hh = h * 6
        
        if hh < 1 {
            r = c; g = x; b = 0
        } else if hh < 2 {
            r = x; g = c; b = 0
        } else if hh < 3 {
            r = 0; g = c; b = x
        } else if hh < 4 {
            r = 0; g = x; b = c
        } else if hh < 5 {
            r = x; g = 0; b = c
        } else {
            r = c; g = 0; b = x
        }
        
        return (Float(r + m), Float(g + m), Float(b + m))
    }
}
