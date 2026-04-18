import SwiftUI
import AVFoundation

struct MainCameraView: View {
    @StateObject private var cameraManager = CameraManager.shared
    @State private var showSettings = false
    @State private var showProcessingIndicator = false
    @State private var isRecording = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            CameraPreviewView(cameraManager: cameraManager)
                .ignoresSafeArea()
            
            if cameraManager.settings.gridEnabled {
                GridOverlay()
                    .allowsHitTesting(false)
            }
            
            VStack(spacing: 0) {
                ControlsOverlay(cameraManager: cameraManager, showSettings: $showSettings)
                
                Spacer()
                
                ZoomControlView(zoomFactor: $cameraManager.settings.zoomFactor)
                    .padding(.bottom, 12)
                
                ModeSelectorView(selectedMode: $cameraManager.currentMode)
                    .padding(.bottom, 8)
                    .onChange(of: cameraManager.currentMode) { newMode in
                        cameraManager.switchMode(newMode)
                    }
                
                HStack {
                    GalleryThumbnailView(onTap: {
                        // Open gallery
                    })
                    .padding(.leading, 24)
                    
                    Spacer()
                    
                    if cameraManager.currentMode == .video {
                        VideoRecordButton(isRecording: isRecording) {
                            isRecording.toggle()
                        }
                    } else {
                        ShutterButton(
                            mode: cameraManager.currentMode,
                            isCapturing: cameraManager.isCapturing,
                            action: {
                                Task {
                                    do {
                                        try await cameraManager.captureWithProcessing()
                                    } catch {
                                        print("Capture error: \(error)")
                                    }
                                }
                            },
                            longPressAction: nil
                        )
                    }
                    
                    Spacer()
                    
                    LiquidGlassCircleButton(systemName: "arrow.triangle.2.circlepath.camera", size: 44) {
                        // Switch camera front/back
                    }
                    .padding(.trailing, 24)
                }
                .padding(.bottom, 32)
            }
            
            if showSettings {
                SettingsView(isPresented: $showSettings, cameraManager: cameraManager)
            }
            
            if cameraManager.isCapturing || cameraManager.processingState != .idle && cameraManager.processingState != .complete {
                ProcessingIndicator(state: cameraManager.processingState)
                    .transition(.opacity)
            }
        }
        .task {
            do {
                try await cameraManager.setupSession()
                cameraManager.startSession()
            } catch {
                print("Setup error: \(error)")
            }
        }
    }
}

struct CameraPreviewView: UIViewRepresentable {
    let cameraManager: CameraManager
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        view.backgroundColor = .black
        
        if let previewLayer = cameraManager.previewLayer {
            previewLayer.frame = view.bounds
            view.layer.addSublayer(previewLayer)
        }
        
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tapGesture)
        
        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        view.addGestureRecognizer(pinchGesture)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        cameraManager.previewLayer?.frame = uiView.bounds
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(cameraManager: cameraManager)
    }
    
    class Coordinator: NSObject {
        let cameraManager: CameraManager
        
        init(cameraManager: CameraManager) {
            self.cameraManager = cameraManager
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            let point = gesture.location(in: gesture.view)
            let focusPoint = CGPoint(x: point.y / gesture.view!.bounds.height, y: 1.0 - point.x / gesture.view!.bounds.width)
            cameraManager.focus(at: focusPoint)
        }
        
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            let currentZoom = cameraManager.settings.zoomFactor
            let newZoom = currentZoom * gesture.scale
            cameraManager.setZoom(max(0.5, min(5.0, newZoom)))
            gesture.scale = 1.0
        }
    }
}

struct GridOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                HStack {
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 0.5)
                    Spacer()
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 0.5)
                    Spacer()
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 0.5)
                }
                
                VStack {
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 0.5)
                    Spacer()
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 0.5)
                    Spacer()
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 0.5)
                }
            }
        }
    }
}

struct ProcessingIndicator: View {
    let state: ProcessingState
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            
            LiquidGlassPanel(cornerRadius: 24, opacity: 0.25) {
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.2)
                    
                    Text(state.description)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                    
                    if let progress = state.progress {
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.15))
                                    .frame(height: 4)
                                
                                Capsule()
                                    .fill(Color.white)
                                    .frame(width: geometry.size.width * CGFloat(progress), height: 4)
                                    .animation(.easeInOut(duration: 0.3), value: progress)
                            }
                        }
                        .frame(width: 160, height: 4)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
            }
        }
    }
}

#Preview {
    MainCameraView()
}
