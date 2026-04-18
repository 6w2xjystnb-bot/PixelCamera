import SwiftUI

struct LiquidGlassButton: View {
    let title: String?
    let systemImage: String?
    let action: () -> Void
    var isSelected: Bool = false
    var size: CGSize = CGSize(width: 56, height: 56)
    
    @State private var isPressed = false
    
    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(isSelected ? 0.35 : 0.15)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(isSelected ? 0.5 : 0.25), lineWidth: isSelected ? 1 : 0.5)
                    )
                
                if let systemImage = systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.9))
                }
                
                if let title = title {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isSelected ? .white : .white.opacity(0.9))
                }
            }
            .frame(width: size.width, height: size.height)
            .scaleEffect(isPressed ? 0.92 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isPressed)
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
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

struct PressEventsModifier: ViewModifier {
    var onPress: () -> Void
    var onRelease: () -> Void
    
    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        onPress()
                    }
                    .onEnded { _ in
                        onRelease()
                    }
            )
    }
}

extension View {
    func pressEvents(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) -> some View {
        modifier(PressEventsModifier(onPress: onPress, onRelease: onRelease))
    }
}

struct LiquidGlassToggle: View {
    let title: String
    @Binding var isOn: Bool
    
    var body: some View {
        Button(action: { isOn.toggle() }) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                Spacer()
                ZStack {
                    Capsule()
                        .fill(isOn ? Color.white.opacity(0.3) : Color.white.opacity(0.1))
                        .frame(width: 44, height: 26)
                    
                    Circle()
                        .fill(.white)
                        .frame(width: 20, height: 20)
                        .offset(x: isOn ? 8 : -8)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isOn)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(0.15)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 20) {
            LiquidGlassButton(title: nil, systemImage: "bolt.fill", action: {}, isSelected: true)
            LiquidGlassButton(title: "HDR+", systemImage: nil, action: {}, isSelected: false, size: CGSize(width: 80, height: 40))
        }
    }
}
