import SwiftUI

struct ModeSelectorView: View {
    @Binding var selectedMode: CaptureMode
    @Namespace private var animation
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CaptureMode.allCases) { mode in
                        ModeButton(
                            mode: mode,
                            isSelected: selectedMode == mode,
                            namespace: animation
                        ) {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                selectedMode = mode
                            }
                        }
                        .id(mode.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .onChange(of: selectedMode) { newValue in
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(newValue.id, anchor: .center)
                }
            }
        }
    }
}

struct ModeButton: View {
    let mode: CaptureMode
    let isSelected: Bool
    var namespace: Namespace.ID
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                if isSelected {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .opacity(0.35)
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.4), lineWidth: 0.5)
                        )
                        .matchedGeometryEffect(id: "modeSelector", in: namespace)
                }
                
                HStack(spacing: 6) {
                    Image(systemName: mode.iconName)
                        .font(.system(size: 14, weight: .medium))
                    
                    Text(mode.shortLabel)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                }
                .foregroundStyle(isSelected ? .white : .white.opacity(0.6))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        ModeSelectorView(selectedMode: .constant(.photo))
    }
}
