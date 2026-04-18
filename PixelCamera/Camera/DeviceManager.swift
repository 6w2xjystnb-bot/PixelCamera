import Foundation
import AVFoundation

final class DeviceManager: ObservableObject {
    static let shared = DeviceManager()
    
    @Published var currentDevice: AVCaptureDevice?
    @Published var availableDevices: [AVCaptureDevice] = []
    @Published var zoomFactor: CGFloat = 1.0
    @Published var isUltraWideAvailable = false
    @Published var isTelephotoAvailable = false
    
    private let discoverySession = AVCaptureDevice.DiscoverySession(
        deviceTypes: [.builtInTripleCamera, .builtInDualCamera, .builtInDualWideCamera, .builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera],
        mediaType: .video,
        position: .back
    )
    
    private init() {
        refreshDevices()
    }
    
    func refreshDevices() {
        let devices = discoverySession.devices
        availableDevices = devices
        
        isUltraWideAvailable = devices.contains { $0.deviceType == .builtInUltraWideCamera }
        isTelephotoAvailable = devices.contains { $0.deviceType == .builtInTelephotoCamera }
        
        if currentDevice == nil {
            currentDevice = devices.first { $0.deviceType == .builtInWideAngleCamera } ?? devices.first
        }
    }
    
    func device(for type: AVCaptureDevice.DeviceType, position: AVCaptureDevice.Position = .back) -> AVCaptureDevice? {
        return availableDevices.first { $0.deviceType == type && $0.position == position }
    }
    
    func selectDevice(_ device: AVCaptureDevice) {
        currentDevice = device
    }
    
    func selectLens(_ lens: CameraSettings.PreferredLens) {
        switch lens {
        case .ultraWide:
            if let device = device(for: .builtInUltraWideCamera) {
                selectDevice(device)
                zoomFactor = 0.5
            }
        case .wide:
            if let device = device(for: .builtInWideAngleCamera) {
                selectDevice(device)
                zoomFactor = 1.0
            }
        case .telephoto:
            if let device = device(for: .builtInTelephotoCamera) {
                selectDevice(device)
                zoomFactor = 3.0
            }
        case .auto:
            if let triple = device(for: .builtInTripleCamera) {
                selectDevice(triple)
            } else if let dual = device(for: .builtInDualCamera) {
                selectDevice(dual)
            } else {
                selectDevice(device(for: .builtInWideAngleCamera)!)
            }
            zoomFactor = 1.0
        }
    }
    
    func setZoom(_ factor: CGFloat) {
        guard let device = currentDevice else { return }
        
        let clamped = max(device.minAvailableVideoZoomFactor, min(factor, device.maxAvailableVideoZoomFactor))
        zoomFactor = clamped
        
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
        } catch {
            print("Failed to set zoom: \(error)")
        }
    }
    
    func rampZoom(to factor: CGFloat, rate: Float = 2.0) {
        guard let device = currentDevice else { return }
        let clamped = max(device.minAvailableVideoZoomFactor, min(factor, device.maxAvailableVideoZoomFactor))
        
        do {
            try device.lockForConfiguration()
            device.ramp(toVideoZoomFactor: clamped, withRate: rate)
            device.unlockForConfiguration()
            zoomFactor = clamped
        } catch {
            print("Failed to ramp zoom: \(error)")
        }
    }
    
    func cancelZoomRamp() {
        guard let device = currentDevice else { return }
        do {
            try device.lockForConfiguration()
            device.cancelVideoZoomRamp()
            device.unlockForConfiguration()
        } catch {
            print("Failed to cancel zoom ramp: \(error)")
        }
    }
    
    var supportsDepthDataOutput: Bool {
        guard let device = currentDevice else { return false }
        return device.activeFormat.isDepthDataFormatSupported
    }
    
    var maxISO: Float {
        currentDevice?.activeFormat.maxISO ?? 0
    }
    
    var minISO: Float {
        currentDevice?.activeFormat.minISO ?? 0
    }
    
    var maxExposureDuration: CMTime {
        currentDevice?.activeFormat.maxExposureDuration ?? CMTime.zero
    }
    
    var minExposureDuration: CMTime {
        currentDevice?.activeFormat.minExposureDuration ?? CMTime.zero
    }
}
