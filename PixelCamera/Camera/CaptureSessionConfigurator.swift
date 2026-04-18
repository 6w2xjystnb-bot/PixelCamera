import Foundation
import AVFoundation

final class CaptureSessionConfigurator {
    nonisolated(unsafe) static let shared = CaptureSessionConfigurator()
    
    private init() {}
    
    func configure(session: AVCaptureSession, for mode: CaptureMode, device: AVCaptureDevice) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        
        session.sessionPreset = .photo
        
        if let existingInput = session.inputs.first as? AVCaptureDeviceInput {
            session.removeInput(existingInput)
        }
        
        let input = try AVCaptureDeviceInput(device: device)
        if session.canAddInput(input) {
            session.addInput(input)
        }
        
        try configureDevice(device, for: mode)
        
        if mode == .video {
            if let existingOutput = session.outputs.first(where: { $0 is AVCaptureMovieFileOutput }) {
                session.removeOutput(existingOutput)
            }
            let movieOutput = AVCaptureMovieFileOutput()
            if session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
            }
        }
    }
    
    func addPhotoOutput(to session: AVCaptureSession) -> AVCapturePhotoOutput? {
        let photoOutput = AVCapturePhotoOutput()
        photoOutput.isHighResolutionCaptureEnabled = true
        photoOutput.isLivePhotoCaptureEnabled = photoOutput.isLivePhotoCaptureSupported
        
        if #available(iOS 26.0, *) {
            photoOutput.maxPhotoQualityPrioritization = .quality
        }
        
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            return photoOutput
        }
        return nil
    }
    
    func addDepthOutput(to session: AVCaptureSession) -> AVCaptureDepthDataOutput? {
        let depthOutput = AVCaptureDepthDataOutput()
        depthOutput.isFilteringEnabled = true
        if session.canAddOutput(depthOutput) {
            session.addOutput(depthOutput)
            return depthOutput
        }
        return nil
    }
    
    private func configureDevice(_ device: AVCaptureDevice, for mode: CaptureMode) throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        
        if device.isSmoothAutoFocusSupported {
            device.isSmoothAutoFocusEnabled = true
        }
        
        if device.isSubjectAreaChangeMonitoringEnabled {
            device.isSubjectAreaChangeMonitoringEnabled = true
        }
        
        switch mode {
        case .nightSight, .astro:
            device.exposureMode = .custom
            if device.isLowLightBoostEnabled {
                device.automaticallyEnablesLowLightBoostWhenAvailable = true
            }
        case .portrait:
            device.focusMode = .continuousAutoFocus
            device.exposureMode = .continuousAutoExposure
        case .photo:
            device.focusMode = .continuousAutoFocus
            device.exposureMode = .continuousAutoExposure
        case .video:
            device.focusMode = .continuousAutoFocus
            device.exposureMode = .continuousAutoExposure
        }
        
        if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            device.whiteBalanceMode = .continuousAutoWhiteBalance
        }
        
        device.automaticallyAdjustsVideoHDREnabled = false
        if device.isVideoHDREnabled {
            device.isVideoHDREnabled = false
        }
    }
    
    func configureForNightSight(device: AVCaptureDevice, iso: Float? = nil, exposureDuration: CMTime? = nil) throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        
        device.exposureMode = .custom
        let duration = exposureDuration ?? CMTime(value: 1, timescale: 15)
        let targetISO = iso ?? min(device.activeFormat.maxISO, 3200)
        let clampedISO = max(device.activeFormat.minISO, min(targetISO, device.activeFormat.maxISO))
        let clampedDuration = CMTimeMaximum(CMTimeMinimum(duration, device.activeFormat.maxExposureDuration), device.activeFormat.minExposureDuration)
        
        device.setExposureModeCustom(duration: clampedDuration, iso: clampedISO)
    }
    
    func configureForAstro(device: AVCaptureDevice, maxDuration: TimeInterval = 240) throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        
        device.exposureMode = .custom
        let duration = CMTime(seconds: min(maxDuration, 16), preferredTimescale: 1)
        let clampedDuration = CMTimeMaximum(CMTimeMinimum(duration, device.activeFormat.maxExposureDuration), device.activeFormat.minExposureDuration)
        let iso = min(device.activeFormat.maxISO, 1600)
        let clampedISO = max(device.activeFormat.minISO, min(iso, device.activeFormat.maxISO))
        
        device.setExposureModeCustom(duration: clampedDuration, iso: clampedISO)
    }
}
