import SwiftUI

struct SettingsView: View {
    @Binding var isPresented: Bool
    @ObservedObject var cameraManager: CameraManager
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        isPresented = false
                    }
                }
            
            VStack(spacing: 0) {
                HStack {
                    Text("Settings")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            isPresented = false
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding()
                
                ScrollView {
                    VStack(spacing: 12) {
                        settingsSection("Capture") {
                            LiquidGlassToggle(title: "Save to Photos", isOn: $cameraManager.settings.saveToPhotos)
                            LiquidGlassToggle(title: "Grid Lines", isOn: $cameraManager.settings.gridEnabled)
                            LiquidGlassToggle(title: "Level Indicator", isOn: $cameraManager.settings.levelEnabled)
                        }
                        
                        settingsSection("Format") {
                            LiquidGlassToggle(title: "RAW (DNG)", isOn: $cameraManager.settings.rawEnabled)
                            LiquidGlassToggle(title: "HEIF", isOn: $cameraManager.settings.heifEnabled)
                        }
                        
                        settingsSection("Location") {
                            LiquidGlassToggle(title: "Save Location", isOn: $cameraManager.settings.locationEnabled)
                        }
                        
                        settingsSection("Astrophotography") {
                            astroDurationPicker
                        }
                        
                        settingsSection("About") {
                            HStack {
                                Text("Version")
                                    .font(.system(size: 15))
                                    .foregroundStyle(.white)
                                Spacer()
                                Text("1.0 (iOS 26)")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(.ultraThinMaterial)
                                    .opacity(0.15)
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                }
            }
            .background(
                LiquidGlassPanel(cornerRadius: 32, opacity: 0.15) {
                    Color.clear
                }
            )
            .frame(maxWidth: 360)
            .padding(.horizontal, 20)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
    
    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .textCase(.uppercase)
                .padding(.horizontal, 4)
            
            VStack(spacing: 8) {
                content()
            }
        }
    }
    
    private var astroDurationPicker: some View {
        HStack {
            Text("Max Duration")
                .font(.system(size: 15))
                .foregroundStyle(.white)
            Spacer()
            Picker("Duration", selection: $cameraManager.settings.astroDuration) {
                ForEach(CameraSettings.AstroDuration.allCases, id: \.self) { duration in
                    Text(duration.rawValue.capitalized)
                        .tag(duration)
                }
            }
            .pickerStyle(.menu)
            .tint(.white)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(0.15)
        )
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        SettingsView(isPresented: .constant(true), cameraManager: CameraManager.shared)
    }
}
