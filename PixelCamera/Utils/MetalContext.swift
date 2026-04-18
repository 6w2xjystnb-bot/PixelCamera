import Foundation
import Metal
import MetalKit

final class MetalContext {
    static let shared = MetalContext()
    
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let defaultLibrary: MTLLibrary
    let textureLoader: MTKTextureLoader
    
    private init?() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported on this device")
            return nil
        }
        guard let commandQueue = device.makeCommandQueue(),
              let defaultLibrary = try? device.makeDefaultLibrary(bundle: Bundle.main),
              let textureLoader = try? MTKTextureLoader(device: device) else {
            return nil
        }
        
        self.device = device
        self.commandQueue = commandQueue
        self.defaultLibrary = defaultLibrary
        self.textureLoader = textureLoader
    }
    
    func makeComputePipeline(functionName: String) -> MTLComputePipelineState? {
        guard let function = defaultLibrary.makeFunction(name: functionName) else {
            print("Failed to find Metal function: \(functionName)")
            return nil
        }
        do {
            return try device.makeComputePipelineState(function: function)
        } catch {
            print("Failed to create compute pipeline for \(functionName): \(error)")
            return nil
        }
    }
    
    func makeRenderPipeline(vertexFunction: String, fragmentFunction: String, pixelFormat: MTLPixelFormat = .bgra8Unorm) -> MTLRenderPipelineState? {
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = defaultLibrary.makeFunction(name: vertexFunction)
        descriptor.fragmentFunction = defaultLibrary.makeFunction(name: fragmentFunction)
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        
        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            print("Failed to create render pipeline: \(error)")
            return nil
        }
    }
    
    func makeTexture(width: Int, height: Int, pixelFormat: MTLPixelFormat = .rgba16Float, usage: MTLTextureUsage = [.shaderRead, .shaderWrite]) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = usage
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)
    }
    
    func makeBuffer<T>(length: Int, options: MTLResourceOptions = .storageModeShared) -> MTLBuffer? {
        return device.makeBuffer(length: length * MemoryLayout<T>.stride, options: options)
    }
    
    func encodeComputePass(
        pipelineState: MTLComputePipelineState,
        textures: [MTLTexture?],
        buffers: [MTLBuffer?] = [],
        threadgroupSize: MTLSize? = nil,
        threadgroupCount: MTLSize? = nil
    ) {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let computeEncoder = commandBuffer.makeComputeCommandEncoder() else { return }
        
        computeEncoder.setComputePipelineState(pipelineState)
        
        for (index, texture) in textures.enumerated() {
            computeEncoder.setTexture(texture, index: index)
        }
        
        for (index, buffer) in buffers.enumerated() {
            computeEncoder.setBuffer(buffer, offset: 0, index: index)
        }
        
        let tgSize = threadgroupSize ?? MTLSize(width: 16, height: 16, depth: 1)
        let tgCount = threadgroupCount ?? MTLSize(
            width: max(1, (textures.compactMap { $0 }.first?.width ?? 1) / tgSize.width),
            height: max(1, (textures.compactMap { $0 }.first?.height ?? 1) / tgSize.height),
            depth: 1
        )
        
        computeEncoder.dispatchThreadgroups(tgCount, threadsPerThreadgroup: tgSize)
        computeEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
}
