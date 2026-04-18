import SwiftUI

struct ShutterButton: View {
    let mode: CaptureMode
    let isCapturing: Bool
    let action: () -> Void
    let longPressAction: (() -> Void)?
    
    @State private var isPressed = false
    @State private var pressProgress: CGFloat = 0
    @State private var captureAnimation = false
    
    private var outerColor: Color {
        switch mode {
        case .photo, .superRes: return .white
        case .nightSight: return .indigo
        case .portrait: return .pink
        case .astro: return .cyan
        case .video: return .red
        }
    }
    
    private var innerColor: Color {
        switch mode {
        case .photo, .superRes: return .white
        case .nightSight: return .indigo.opacity(0.8)
        case .portrait: return .pink.opacity(0.8)
        case .astro: return .cyan.opacity(0.8)
        case .video: return .red
        }
    }
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(outerColor.opacity(0.6), lineWidth: 4)
                .frame(width: 78, height: 78)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .opacity(0.1)
                )
            
            Circle()
                .fill(innerColor)
                .frame(width: isCapturing ? 28 : 62, height: isCapturing ? 28 : 62)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                )
                .scaleEffect(isPressed ? 0.85 : 1.0)
                .animation(.spring(response: 0.25, dampingFraction: 0.5), value: isPressed)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isCapturing)
            
            if isCapturing {
                Circle()
                    .stroke(outerColor, lineWidth: 3)
                    .frame(width: 86, height: 86)
                    .scaleEffect(captureAnimation ? 1.2 : 1.0)
                    .opacity(captureAnimation ? 0 : 0.6)
                    .animation(.easeOut(duration: 0.6).repeatForever(autoreverses: false), value: captureAnimation)
                    .onAppear {
                        captureAnimation = true
                    }
            }
        }
        .frame(width: 100, height: 100)
        .contentShape(Circle())
        .onTapGesture {
            action()
        }
        .onLongPressGesture(minimumDuration: 0.5, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.15)) {
                isPressed = pressing
            }
        }) {
            longPressAction?()
        }
    }
}

struct VideoRecordButton: View {
    let isRecording: Bool
    let action: () -> Void
    
    @State private var isPressed = false
    
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.5), lineWidth: 4)
                .frame(width: 72, height: 72)
            
            RoundedRectangle(cornerRadius: isRecording ? 8 : 32, style: .continuous)
                .fill(isRecording ? .red : .red)
                .frame(width: isRecording ? 28 : 56, height: isRecording ? 28 : 56)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isRecording)
                .scaleEffect(isPressed ? 0.88 : 1.0)
        }
        .frame(width: 100, height: 100)
        .contentShape(Circle())
        .onTapGesture {
            action()
        }
        .pressEvents {
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = true
            }
        } onRelease: {
            withAnimation(.easeInOut(duration: 0.2)) {
                isPressed = false
            }
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 40) {
            ShutterButton(mode: .photo, isCapturing: false, action: {}, longPressAction: nil)
            ShutterButton(mode: .nightSight, isCapturing: true, action: {}, longPressAction: nil)
            VideoRecordButton(isRecording: false, action: {})
            VideoRecordButton(isRecording: true, action: {})
        }
    }
}
