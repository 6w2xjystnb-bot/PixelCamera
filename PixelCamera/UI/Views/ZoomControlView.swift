import SwiftUI

struct ZoomControlView: View {
    @Binding var zoomFactor: CGFloat
    let deviceManager = DeviceManager.shared
    
    @State private var isExpanded = false
    @State private var dragOffset: CGFloat = 0
    
    private let zoomLevels: [CGFloat] = [0.5, 1.0, 2.0, 3.0, 5.0]
    private let labels = ["0.5x", "1x", "2x", "3x", "5x"]
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(zoomLevels.enumerated()), id: \.element) { index, level in
                ZoomButton(
                    label: labels[index],
                    isSelected: abs(zoomFactor - level) < 0.3,
                    action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            zoomFactor = level
                            deviceManager.rampZoom(to: level)
                        }
                    }
                )
            }
        }
        .padding(4)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .opacity(0.2)
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
        )
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = value.translation.width
                    let sensitivity: CGFloat = 0.005
                    let delta = -dragOffset * sensitivity
                    let newZoom = max(0.5, min(5.0, zoomFactor + delta))
                    zoomFactor = newZoom
                    deviceManager.setZoom(newZoom)
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        dragOffset = 0
                        let closest = zoomLevels.min { abs($0 - zoomFactor) < abs($1 - zoomFactor) } ?? 1.0
                        zoomFactor = closest
                        deviceManager.rampZoom(to: closest)
                    }
                }
        )
    }
}

struct ZoomButton: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? .black : .white)
                .frame(width: 44, height: 32)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.white : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        ZoomControlView(zoomFactor: .constant(1.0))
    }
}
