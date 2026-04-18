# PixelCamera

A computational photography camera app for iOS 26, inspired by Google Camera on Pixel phones. Built with SwiftUI, Liquid Glass design language, and a complete Metal-accelerated image processing pipeline.

## Features

### Capture Modes
- **Photo** — Standard capture with HDR+ processing
- **Night Sight** — Computational low-light photography with motion-adaptive stacking
- **Portrait** — Depth-aware bokeh with hair refinement
- **Astro** — Long-exposure star photography with earth rotation compensation
- **Video** — Standard video recording

### Computational Photography Pipeline

#### HDR+ (High Dynamic Range Plus)
- **Burst Capture**: 8-15 RAW frames
- **Tile-based Alignment**: Spatial domain block matching with 16x16 tiles and 8px search radius
- **Wiener Filter Merge**: Frequency-domain weighted temporal averaging with per-tile confidence
- **Mertens Tone Mapping**: Local bilateral tone mapping with detail enhancement
- **Dehazing**: Dark channel prior with guided filter transmission estimation
- **Veiling Glare Removal**: Local minimum subtraction for atmospheric scattering
- **Color Tuning**: Hue-specific adjustments (cyan→blue shift, saturation boost)

#### Night Sight
- **Motion Meter**: Gyroscope/accelerometer-based hand-shake detection
- **Adaptive Frame Count**: 6-15 frames based on motion stability
- **Long Exposure Simulation**: Motion-compensated temporal stacking with outlier rejection
- **Multi-scale Bilateral Noise Reduction**: Edge-preserving denoising at multiple scales
- **Auto White Balance**: Gray world + white patch hybrid for low-light scenes
- **Luminance Sharpening**: Unsharp mask with adaptive strength

#### Portrait Mode
- **Depth Estimation**: AVDepthData when available, fallback to edge-based estimation
- **Matte Generation**: Otsu thresholding with morphological close and edge feathering
- **Hexagonal Bokeh**: Custom aperture-shaped blur kernel simulating real lens bokeh
- **Hair Refinement**: Edge-aware guided filter preserving fine detail at subject boundaries

#### Super Res Zoom
- **Subpixel Alignment**: Phase correlation for subpixel shift estimation
- **Detail Reconstruction**: Frequency-domain blending — temporal average for low frequencies, sharpest frame for high frequencies
- **Gradient Sharpening**: Laplacian-based detail enhancement

#### Astrophotography
- **Star Tracking**: Gyroscope-based earth rotation compensation + brightest-point star alignment
- **Dark Frame Subtraction**: Hot pixel detection with neighbor interpolation
- **Star Stacking**: Sigma-clipped median stacking with foreground preservation
- **Tone Mapping**: Exposure boost and gamma adjustment optimized for night sky

### UI/UX
- **Liquid Glass Design**: iOS 26 translucent panels with light refraction, frosted materials, and fluid animations
- **Real-time Preview**: AVCaptureVideoPreviewLayer with tap-to-focus and pinch-to-zoom
- **Mode Selector**: Horizontal scroll with animated selection indicator
- **Shutter Button**: Liquid Glass button with mode-specific colors and press animations
- **Exposure Controls**: Sliders for EV, ISO, and manual focus
- **Zoom Rocker**: 0.5x–5x with tactile switching between lens focal lengths

## Architecture

```
PixelCamera/
├── App/
│   ├── PixelCameraApp.swift          # @main SwiftUI entry
│   └── SceneDelegate.swift           # UIWindowScene configuration
├── UI/
│   ├── Views/
│   │   ├── MainCameraView.swift      # Main camera screen
│   │   ├── ModeSelectorView.swift    # Capture mode selector
│   │   ├── ShutterButton.swift       # Animated shutter button
│   │   ├── ControlsOverlay.swift     # Exposure/ISO/focus
│   │   ├── ZoomControlView.swift     # Zoom rocker
│   │   ├── GalleryThumbnailView.swift # Last photo preview
│   │   └── SettingsView.swift        # App settings
│   └── Components/
│       ├── LiquidGlassPanel.swift    # Reusable glass container
│       └── LiquidGlassButton.swift   # Reusable glass button
├── Camera/
│   ├── CameraManager.swift           # AVCaptureSession orchestrator
│   ├── CaptureSessionConfigurator.swift # Input/output setup
│   ├── PhotoCaptureDelegate.swift    # AVCapturePhotoCaptureDelegate
│   └── DeviceManager.swift           # Lens/zoom management
├── Processing/
│   ├── HDRPlus/
│   │   ├── HDRPlusProcessor.swift    # Main coordinator
│   │   ├── BurstCaptureManager.swift # Frame collection
│   │   ├── FrameAligner.swift        # Tile-based alignment
│   │   ├── BurstMerger.swift         # Wiener filter merge
│   │   ├── ToneMapper.swift          # Local tone mapping
│   │   ├── Dehazer.swift             # Veiling glare removal
│   │   └── ColorTuner.swift          # Hue adjustments
│   ├── NightSight/
│   │   ├── NightSightProcessor.swift # Main coordinator
│   │   ├── MotionMeter.swift         # Motion analysis
│   │   ├── LongExposureSimulator.swift # Stacked exposures
│   │   ├── NoiseReducer.swift        # Bilateral denoising
│   │   └── AutoWhiteBalancer.swift   # Low-light AWB
│   ├── Portrait/
│   │   ├── PortraitProcessor.swift   # Main coordinator
│   │   ├── DepthEstimator.swift      # Depth map generation
│   │   ├── MatteGenerator.swift      # Alpha matte refinement
│   │   ├── BokehRenderer.swift       # Bokeh blur
│   │   └── HairRefiner.swift         # Edge refinement
│   ├── SuperRes/
│   │   ├── SuperResProcessor.swift   # Main coordinator
│   │   ├── SubpixelAligner.swift     # Subpixel alignment
│   │   └── DetailReconstructor.swift # High-freq detail recovery
│   └── Astro/
│       ├── AstroProcessor.swift      # Main coordinator
│       ├── StarTracker.swift         # Star motion compensation
│       ├── DarkFrameSubtractor.swift # Hot pixel removal
│       └── StarStacker.swift         # Sigma-clip star stacking
├── Shaders/
│   ├── HDRPlusShaders.metal          # Alignment, merge, tone map
│   ├── PortraitShaders.metal         # Bokeh, matte, depth
│   ├── NightSightShaders.metal       # Denoise, sharpen, WB
│   └── SuperResShaders.metal         # Detail reconstruction
├── Utils/
│   ├── MetalContext.swift            # Metal device/context
│   ├── TextureLoader.swift           # Texture utilities
│   ├── ImageBufferExtensions.swift   # CVPixelBuffer helpers
│   ├── CameraPermissions.swift       # Permission handling
│   └── PhotoLibrarySaver.swift       # Save to Photos
└── Models/
    ├── CaptureMode.swift             # Mode enum
    ├── ProcessingState.swift         # Pipeline states
    └── CameraSettings.swift          # Settings model
```

## Build Requirements

- **iOS 26.0+**
- **Xcode 26.0+**
- **Swift 6.0**
- **Metal 3**
- Device with A12 Bionic or later (for best performance)

## Build Instructions

### Xcode
1. Open `PixelCamera.xcodeproj`
2. Select your target device or simulator
3. Build and run (⌘+R)

### Command Line
```bash
cd PixelCamera
xcodebuild -project PixelCamera.xcodeproj -scheme PixelCamera -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

## Permissions

The app requires the following permissions:
- **Camera** — for photo and video capture
- **Microphone** — for video audio recording
- **Photos** — to save captures to library
- **Motion** — for Night Sight and Astro stabilization

## Algorithms

### HDR+ Tile Alignment
Each frame is divided into 16×16 tiles. For each tile, an exhaustive search within an 8-pixel radius computes the Sum of Absolute Differences (SAD) against the reference frame. Subpixel refinement is achieved via gradient-based interpolation around the integer minimum.

### Wiener Filter Merge
In the frequency domain (approximated spatially), each aligned pixel is weighted by:
```
weight = (signal_variance / (signal_variance + noise_variance)) * alignment_confidence
```
This suppresses misaligned regions while averaging stable areas.

### Mertens Exposure Fusion
Local tone mapping computes a bilateral-filtered base layer and a detail layer. The base is compressed with adaptive gamma while the detail is amplified, preserving local contrast without global halo artifacts.

### Night Sight Motion Adaptation
Gyroscope angular velocity and accelerometer data determine hand stability. Thresholds:
- Stable (< 0.5 rad/s): 15 frames, 1/3s exposure
- Moderate (< 2 rad/s): 12 frames, 1/6s exposure
- Shaky (< 5 rad/s): 9 frames, 1/10s exposure
- Very shaky: 6 frames, 1/15s exposure

### Hexagonal Bokeh
The blur kernel samples pixels in a hexagonal pattern weighted by distance from center, simulating a 6-blade aperture. Background pixels are blended with sharp foreground using the depth matte as alpha.

### Astro Star Tracking
Two-stage alignment: gyroscope-based earth rotation compensation (accounting for ~15°/hour) plus brightest-point matching on downsampled star maps. Foreground is detected via temporal consistency and preserved from a single frame.

## License

MIT License — See LICENSE for details.

## Credits

Inspired by Google Camera HDR+ and Night Sight algorithms by Marc Levoy and the Google Research team.
