import SwiftUI

struct LiquidGlassPanel<Content: View>: View {
    var cornerRadius: CGFloat = 24
    var blurRadius: CGFloat = 20
    var saturation: Double = 1.8
    var opacity: Double = 0.15
    var borderOpacity: Double = 0.3
    var innerGlow: Bool = true
    @ViewBuilder var content: Content
    
    var body: some View {
        content
            .padding()
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(opacity)
                    
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.regularMaterial)
                        .opacity(opacity * 0.5)
                        .blendMode(.plusLighter)
                    
                    if innerGlow {
                        RoundedRectangle(cornerRadius: cornerRadius - 2, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                            .blur(radius: 0.5)
                            .padding(1)
                    }
                    
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(borderOpacity), lineWidth: 0.5)
                }
            )
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .backgroundStyle(.ultraThinMaterial)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct LiquidGlassCapsule<Content: View>: View {
    var blurRadius: CGFloat = 20
    var opacity: Double = 0.2
    @ViewBuilder var content: Content
    
    var body: some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .opacity(opacity)
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                    )
            )
            .clipShape(Capsule())
    }
}

struct LiquidGlassCircleButton: View {
    let systemName: String
    let size: CGFloat
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.4, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .opacity(0.2)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.3), lineWidth: 0.5)
                        )
                )
                .clipShape(Circle())
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        LiquidGlassPanel {
            Text("Liquid Glass")
                .foregroundStyle(.white)
        }
    }
}
