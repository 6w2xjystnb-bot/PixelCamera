import Foundation
import AVFoundation

struct CameraSettings: Codable, Equatable {
    var captureMode: CaptureModeRaw = .photo
    var iso: Float = 0 // 0 = auto
    var shutterSpeed: Float = 0 // 0 = auto, in seconds
    var exposureCompensation: Float = 0 // -8 to +8 EV
    var whiteBalance: WhiteBalanceMode = .auto
    var focusMode: FocusMode = .auto
    var manualFocusDistance: Float = 0.5 // 0..1
    var flashMode: FlashMode = .auto
    var timerDuration: TimerDuration = .off
    var gridEnabled: Bool = true
    var levelEnabled: Bool = true
    var rawEnabled: Bool = false
    var heifEnabled: Bool = true
    var locationEnabled: Bool = true
    var saveToPhotos: Bool = true
    var preferredLens: PreferredLens = .auto
    var zoomFactor: CGFloat = 1.0
    var astroDuration: AstroDuration = .auto
    
    enum CaptureModeRaw: String, Codable, CaseIterable {
        case photo, nightSight, portrait, astro, video
        
        var mode: CaptureMode {
            switch self {
            case .photo: return .photo
            case .nightSight: return .nightSight
            case .portrait: return .portrait
            case .astro: return .astro
            case .video: return .video
            }
        }
    }
    
    enum WhiteBalanceMode: String, Codable, CaseIterable {
        case auto, sunny, cloudy, shade, fluorescent, incandescent
        
        var avPreset: AVCaptureDevice.WhiteBalanceMode? {
            switch self {
            case .auto: return .autoWhiteBalance
            default: return .locked
            }
        }
    }
    
    enum FocusMode: String, Codable, CaseIterable {
        case auto, continuous, manual
        
        var avMode: AVCaptureDevice.FocusMode {
            switch self {
            case .auto: return .autoFocus
            case .continuous: return .continuousAutoFocus
            case .manual: return .locked
            }
        }
    }
    
    enum FlashMode: String, Codable, CaseIterable {
        case auto, on, off
        
        var avMode: AVCaptureDevice.FlashMode {
            switch self {
            case .auto: return .auto
            case .on: return .on
            case .off: return .off
            }
        }
    }
    
    enum TimerDuration: String, Codable, CaseIterable {
        case off, three, ten
        
        var seconds: TimeInterval {
            switch self {
            case .off: return 0
            case .three: return 3
            case .ten: return 10
            }
        }
    }
    
    enum PreferredLens: String, Codable, CaseIterable {
        case auto, ultraWide, wide, telephoto
    }
    
    enum AstroDuration: String, Codable, CaseIterable {
        case auto, short, medium, long
        
        var maxSeconds: TimeInterval {
            switch self {
            case .auto: return 240
            case .short: return 60
            case .medium: return 120
            case .long: return 300
            }
        }
    }
}
