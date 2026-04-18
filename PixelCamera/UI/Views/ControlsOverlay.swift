import SwiftUI

struct ControlsOverlay: View {
    @ObservedObject var cameraManager: CameraManager
    @Binding var showSettings: Bool
    @State private var showExposureControls = false
    @State private var showFlashMenu = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                LiquidGlassCircleButton(systemName: flashIcon, size: 44) {
                    cycleFlashMode()
                }
                
                Spacer()
                
                LiquidGlassPanel(cornerRadius: 16, opacity: 0.1) {
                    Text(String(format: "%.1fx", cameraManager.settings.zoomFactor))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 50)
                }
                
                Spacer()
                
                LiquidGlassCircleButton(systemName: "gearshape.fill", size: 44) {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        showSettings.toggle()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            
            Spacer()
            
            if showExposureControls {
                exposureControls
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            HStack(spacing: 20) {
                LiquidGlassCircleButton(systemName: "plusminus.circle", size: 44) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        showExposureControls.toggle()
                    }
                }
                
                Spacer()
                
                if cameraManager.currentMode != .video {
                    LiquidGlassCircleButton(systemName: cameraManager.settings.rawEnabled ? "r.square.fill" : "r.square", size: 44) {
                        cameraManager.settings.rawEnabled.toggle()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
    }
    
    private var exposureControls: some View {
        LiquidGlassPanel(cornerRadius: 20, opacity: 0.2) {
            VStack(spacing: 16) {
                HStack {
                    Text("EV")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                    Slider(value: $cameraManager.settings.exposureCompensation, in: -8...8, step: 0.5)
                        .tint(.white)
                    Text(String(format: "%.1f", cameraManager.settings.exposureCompensation))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 36, alignment: .trailing)
                }
                
                HStack {
                    Text("ISO")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                    Slider(value: $cameraManager.settings.iso, in: 0...3200, step: 100)
                        .tint(.white)
                    Text(cameraManager.settings.iso == 0 ? "Auto" : String(format: "%.0f", cameraManager.settings.iso))
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 36, alignment: .trailing)
                }
                
                HStack {
                    Text("Focus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                    Slider(value: $cameraManager.settings.manualFocusDistance, in: 0...1)
                        .tint(.white)
                    Image(systemName: "scope")
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 280)
        }
        .padding(.bottom, 12)
    }
    
    private var flashIcon: String {
        switch cameraManager.settings.flashMode {
        case .auto: return "bolt.badge.a.fill"
        case .on: return "bolt.fill"
        case .off: return "bolt.slash.fill"
        }
    }
    
    private func cycleFlashMode() {
        switch cameraManager.settings.flashMode {
        case .auto: cameraManager.settings.flashMode = .on
        case .on: cameraManager.settings.flashMode = .off
        case .off: cameraManager.settings.flashMode = .auto
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        ControlsOverlay(cameraManager: CameraManager.shared, showSettings: .constant(false))
    }
}
