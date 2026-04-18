import Foundation
import AVFoundation
import Combine
import CoreMotion
import CoreImage

@MainActor
final class CameraManager: ObservableObject {
    static let shared = CameraManager()
    
    @Published var isRunning = false
    @Published var isCapturing = false
    @Published var processingState: ProcessingState = .idle
    @Published var currentMode: CaptureMode = .photo
    @Published var previewLayer: AVCaptureVideoPreviewLayer?
    @Published var lastCapturedImage: UIImage?
    @Published var captureError: Error?
    @Published var settings = CameraSettings()
    
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.pixelcamera.session")
    private var photoOutput: AVCapturePhotoOutput?
    private var depthOutput: AVCaptureDepthDataOutput?
    private var movieOutput: AVCaptureMovieFileOutput?
    private var videoOutput: AVCaptureVideoDataOutput?
    
    private let deviceManager = DeviceManager.shared
    private let configurator = CaptureSessionConfigurator.shared
    private let motionManager = CMMotionManager()
    private var cancellables = Set<AnyCancellable>()
    
    private var burstPhotos: [AVCapturePhoto] = []
    private var burstCompletion: ((Result<[AVCapturePhoto], Error>) -> Void)?
    private var expectedBurstCount = 0
    
    private var nightSightProcessor: NightSightProcessor?
    private var hdrPlusProcessor: HDRPlusProcessor?
    private var portraitProcessor: PortraitProcessor?
    private var astroProcessor: AstroProcessor?
    private var superResProcessor: SuperResProcessor?
    
    private init() {
        setupNotifications()
    }
    
    private func setupNotifications() {
        NotificationCenter.default.publisher(for: .cameraShouldResume)
            .sink { [weak self] _ in
                self?.startSession()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .cameraShouldPause)
            .sink { [weak self] _ in
                self?.stopSession()
            }
            .store(in: &cancellables)
    }
    
    func setupSession() async throws {
        let permissions = await CameraPermissions.shared.requestAllPermissions()
        guard permissions.camera else {
            throw CameraError.permissionDenied
        }
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                try self.configureSession()
                DispatchQueue.main.async {
                    self.previewLayer = AVCaptureVideoPreviewLayer(session: self.session)
                    self.previewLayer?.videoGravity = .resizeAspectFill
                }
            } catch {
                DispatchQueue.main.async {
                    self.captureError = error
                }
            }
        }
    }
    
    private func configureSession() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        
        session.sessionPreset = .photo
        
        guard let device = deviceManager.currentDevice else {
            throw CameraError.noDeviceAvailable
        }
        
        let input = try AVCaptureDeviceInput(device: device)
        if session.canAddInput(input) {
            session.addInput(input)
        }
        
        photoOutput = configurator.addPhotoOutput(to: session)
        
        if currentMode.usesDepth {
            depthOutput = configurator.addDepthOutput(to: session)
        }
        
        if currentMode == .video {
            let movieOutput = AVCaptureMovieFileOutput()
            if session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
                self.movieOutput = movieOutput
            }
            
            let audioDevice = AVCaptureDevice.default(for: .audio)
            if let audioDevice = audioDevice {
                let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                if session.canAddInput(audioInput) {
                    session.addInput(audioInput)
                }
            }
        }
    }
    
    func startSession() {
        guard !session.isRunning else { return }
        sessionQueue.async { [weak self] in
            self?.session.startRunning()
            DispatchQueue.main.async {
                self?.isRunning = true
            }
        }
    }
    
    func stopSession() {
        guard session.isRunning else { return }
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
            DispatchQueue.main.async {
                self?.isRunning = false
            }
        }
    }
    
    func switchMode(_ mode: CaptureMode) {
        guard mode != currentMode else { return }
        currentMode = mode
        settings.captureMode = mode.captureModeRaw
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                try self.configureSession()
            } catch {
                DispatchQueue.main.async {
                    self.captureError = error
                }
            }
        }
        
        NotificationCenter.default.post(name: .captureModeDidChange, object: mode)
    }
    
    func capturePhoto() async throws -> UIImage {
        return try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: CameraError.sessionNotRunning)
                    return
                }
                
                guard let photoOutput = self.photoOutput else {
                    continuation.resume(throwing: CameraError.noOutput)
                    return
                }
                
                self.isCapturing = true
                
                let settings = AVCapturePhotoSettings()
                if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                    settings.formatType = .hevc
                }
                settings.isHighResolutionPhotoEnabled = true
                
                if #available(iOS 26.0, *) {
                    settings.photoQualityPrioritization = .quality
                }
                
                if self.currentMode.supportsRaw, self.settings.rawEnabled {
                    if let rawType = photoOutput.availableRawPhotoPixelFormatTypes.first {
                        settings.rawPhotoPixelFormatType = rawType
                    }
                }
                
                if self.currentMode.usesDepth, photoOutput.isDepthDataDeliverySupported {
                    settings.isDepthDataDeliveryEnabled = true
                }
                
                let delegate = PhotoCaptureDelegate { result in
                    DispatchQueue.main.async {
                        self.isCapturing = false
                        switch result {
                        case .success(let photo):
                            if let data = photo.fileDataRepresentation(),
                               let image = UIImage(data: data) {
                                self.lastCapturedImage = image
                                continuation.resume(returning: image)
                            } else {
                                continuation.resume(throwing: CameraError.imageConversionFailed)
                            }
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    }
                }
                
                photoOutput.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }
    
    func captureBurst(count: Int, mode: CaptureMode) async throws -> [AVCapturePhoto] {
        return try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: CameraError.sessionNotRunning)
                    return
                }
                
                guard let photoOutput = self.photoOutput else {
                    continuation.resume(throwing: CameraError.noOutput)
                    return
                }
                
                self.expectedBurstCount = count
                self.burstPhotos = []
                self.isCapturing = true
                
                let semaphore = DispatchSemaphore(value: 1)
                var capturedPhotos: [AVCapturePhoto] = []
                var captureError: Error?
                
                let group = DispatchGroup()
                
                for i in 0..<count {
                    group.enter()
                    
                    let photoSettings = AVCapturePhotoSettings()
                    photoSettings.isHighResolutionPhotoEnabled = false
                    
                    if mode.supportsRaw {
                        if let rawType = photoOutput.availableRawPhotoPixelFormatTypes.first {
                            photoSettings.rawPhotoPixelFormatType = rawType
                        }
                    }
                    
                    let delegate = PhotoCaptureDelegate { result in
                        semaphore.wait()
                        switch result {
                        case .success(let photo):
                            capturedPhotos.append(photo)
                            DispatchQueue.main.async {
                                self.processingState = .capturing(frame: capturedPhotos.count, total: count)
                            }
                        case .failure(let error):
                            captureError = error
                        }
                        semaphore.signal()
                        group.leave()
                    }
                    
                    photoOutput.capturePhoto(with: photoSettings, delegate: delegate)
                    
                    if i < count - 1 {
                        usleep(50000)
                    }
                }
                
                group.notify(queue: .main) { [weak self] in
                    self?.isCapturing = false
                    if let error = captureError {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: capturedPhotos)
                    }
                }
            }
        }
    }
    
    func processBurstPhotos(_ photos: [AVCapturePhoto], mode: CaptureMode) async throws -> CIImage {
        switch mode {
        case .photo:
            if hdrPlusProcessor == nil {
                hdrPlusProcessor = HDRPlusProcessor()
            }
            return try await hdrPlusProcessor!.process(photos: photos)
            
        case .nightSight:
            if nightSightProcessor == nil {
                nightSightProcessor = NightSightProcessor()
            }
            return try await nightSightProcessor!.process(photos: photos, motionData: collectMotionData())
            
        case .portrait:
            if portraitProcessor == nil {
                portraitProcessor = PortraitProcessor()
            }
            return try await portraitProcessor!.process(photos: photos)
            
        case .astro:
            if astroProcessor == nil {
                astroProcessor = AstroProcessor()
            }
            return try await astroProcessor!.process(photos: photos, motionData: collectMotionData())
            
        case .video:
            throw CameraError.invalidMode
        }
    }
    
    func captureWithProcessing() async throws {
        let frameCount = currentMode.typicalFrameCount.lowerBound
        let photos = try await captureBurst(count: frameCount, mode: currentMode)
        let processedImage = try await processBurstPhotos(photos, mode: currentMode)
        
        try await PhotoLibrarySaver.shared.save(ciImage: processedImage)
        
        DispatchQueue.main.async {
            self.processingState = .complete
            self.lastCapturedImage = UIImage(ciImage: processedImage)
            NotificationCenter.default.post(name: .captureDidComplete, object: processedImage)
        }
    }
    
    private func collectMotionData() -> [CMDeviceMotion] {
        var motions: [CMDeviceMotion] = []
        guard motionManager.isDeviceMotionAvailable else { return motions }
        
        motionManager.deviceMotionUpdateInterval = 0.01
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { motion, _ in
            if let motion = motion {
                motions.append(motion)
            }
        }
        
        Thread.sleep(forTimeInterval: 0.5)
        motionManager.stopDeviceMotionUpdates()
        return motions
    }
    
    func setZoom(_ factor: CGFloat) {
        deviceManager.setZoom(factor)
    }
    
    func setExposure(targetBias: Float) {
        guard let device = deviceManager.currentDevice else { return }
        do {
            try device.lockForConfiguration()
            device.setExposureTargetBias(targetBias)
            device.unlockForConfiguration()
        } catch {
            print("Failed to set exposure: \(error)")
        }
    }
    
    func setISO(_ iso: Float) {
        guard let device = deviceManager.currentDevice else { return }
        do {
            try device.lockForConfiguration()
            let clampedISO = max(device.activeFormat.minISO, min(iso, device.activeFormat.maxISO))
            device.setExposureModeCustom(duration: AVCaptureDevice.currentExposureDuration, iso: clampedISO)
            device.unlockForConfiguration()
        } catch {
            print("Failed to set ISO: \(error)")
        }
    }
    
    func updateProcessingState(_ state: ProcessingState) {
        DispatchQueue.main.async {
            self.processingState = state
        }
    }
    
    func setFocusMode(_ mode: AVCaptureDevice.FocusMode) {
        guard let device = deviceManager.currentDevice else { return }
        do {
            try device.lockForConfiguration()
            if device.isFocusModeSupported(mode) {
                device.focusMode = mode
            }
            device.unlockForConfiguration()
        } catch {
            print("Failed to set focus mode: \(error)")
        }
    }
    
    func setWhiteBalance(_ mode: AVCaptureDevice.WhiteBalanceMode) {
        guard let device = deviceManager.currentDevice else { return }
        do {
            try device.lockForConfiguration()
            if device.isWhiteBalanceModeSupported(mode) {
                device.whiteBalanceMode = mode
            }
            device.unlockForConfiguration()
        } catch {
            print("Failed to set white balance: \(error)")
        }
    }
    
    func focus(at point: CGPoint) {
        guard let device = deviceManager.currentDevice else { return }
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
                device.exposureMode = .autoExpose
            }
            device.unlockForConfiguration()
        } catch {
            print("Failed to focus: \(error)")
        }
    }
}

enum CameraError: Error, LocalizedError {
    case permissionDenied
    case noDeviceAvailable
    case sessionNotRunning
    case noOutput
    case imageConversionFailed
    case invalidMode
    case processingFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Camera permission denied"
        case .noDeviceAvailable: return "No camera device available"
        case .sessionNotRunning: return "Camera session is not running"
        case .noOutput: return "No photo output configured"
        case .imageConversionFailed: return "Failed to convert captured data to image"
        case .invalidMode: return "Invalid capture mode for this operation"
        case .processingFailed(let msg): return "Processing failed: \(msg)"
        }
    }
}
