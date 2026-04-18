import Foundation

enum CaptureMode: String, CaseIterable, Identifiable {
    case photo = "Photo"
    case nightSight = "Night Sight"
    case portrait = "Portrait"
    case astro = "Astro"
    case video = "Video"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .photo: return "camera.fill"
        case .nightSight: return "moon.stars.fill"
        case .portrait: return "person.crop.rectangle.fill"
        case .astro: return "star.fill"
        case .video: return "video.fill"
        }
    }
    
    var shortLabel: String {
        switch self {
        case .photo: return "Photo"
        case .nightSight: return "Night"
        case .portrait: return "Portrait"
        case .astro: return "Astro"
        case .video: return "Video"
        }
    }
    
    var requiresBurst: Bool {
        switch self {
        case .photo, .nightSight, .astro: return true
        case .portrait: return true
        case .video: return false
        }
    }
    
    var typicalFrameCount: ClosedRange<Int> {
        switch self {
        case .photo: return 8...15
        case .nightSight: return 6...15
        case .portrait: return 3...5
        case .astro: return 15...60
        case .video: return 0...0
        }
    }
    
    var supportsRaw: Bool {
        switch self {
        case .photo, .nightSight, .astro: return true
        case .portrait, .video: return false
        }
    }
    
    var usesDepth: Bool {
        self == .portrait
    }
}
