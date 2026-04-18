import Foundation

enum ProcessingState: Equatable {
    case idle
    case capturing(frame: Int, total: Int)
    case aligning(frame: Int, total: Int)
    case merging(progress: Double)
    case toneMapping(progress: Double)
    case denoising(progress: Double)
    case depthProcessing(progress: Double)
    case bokehRendering(progress: Double)
    case starTracking(progress: Double)
    case stacking(progress: Double)
    case finalizing
    case saving
    case complete
    case failed(Error)
    
    static func == (lhs: ProcessingState, rhs: ProcessingState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.capturing(let l, let lt), .capturing(let r, let rt)): return l == r && lt == rt
        case (.aligning(let l, let lt), .aligning(let r, let rt)): return l == r && lt == rt
        case (.merging(let l), .merging(let r)): return l == r
        case (.toneMapping(let l), .toneMapping(let r)): return l == r
        case (.denoising(let l), .denoising(let r)): return l == r
        case (.depthProcessing(let l), .depthProcessing(let r)): return l == r
        case (.bokehRendering(let l), .bokehRendering(let r)): return l == r
        case (.starTracking(let l), .starTracking(let r)): return l == r
        case (.stacking(let l), .stacking(let r)): return l == r
        case (.finalizing, .finalizing): return true
        case (.saving, .saving): return true
        case (.complete, .complete): return true
        case (.failed, .failed): return true
        default: return false
        }
    }
    
    var description: String {
        switch self {
        case .idle: return "Ready"
        case .capturing(let frame, let total): return "Capturing \(frame)/\(total)"
        case .aligning(let frame, let total): return "Aligning \(frame)/\(total)"
        case .merging: return "Merging frames"
        case .toneMapping: return "Tone mapping"
        case .denoising: return "Reducing noise"
        case .depthProcessing: return "Processing depth"
        case .bokehRendering: return "Rendering bokeh"
        case .starTracking: return "Tracking stars"
        case .stacking: return "Stacking frames"
        case .finalizing: return "Finalizing"
        case .saving: return "Saving"
        case .complete: return "Done"
        case .failed: return "Failed"
        }
    }
    
    var progress: Double? {
        switch self {
        case .capturing(let frame, let total): return Double(frame) / Double(total)
        case .aligning(let frame, let total): return Double(frame) / Double(total)
        case .merging(let p), .toneMapping(let p), .denoising(let p),
             .depthProcessing(let p), .bokehRendering(let p), .starTracking(let p), .stacking(let p):
            return p
        default: return nil
        }
    }
}
