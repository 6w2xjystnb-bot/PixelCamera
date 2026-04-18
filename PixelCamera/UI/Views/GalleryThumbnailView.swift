import SwiftUI
import Photos

struct GalleryThumbnailView: View {
    @State private var thumbnail: UIImage?
    @State private var isPressed = false
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                if let thumbnail = thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(0.3)
                        .frame(width: 48, height: 48)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundStyle(.white.opacity(0.5))
                        )
                }
                
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    .frame(width: 48, height: 48)
            }
            .scaleEffect(isPressed ? 0.9 : 1.0)
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
        .task {
            await loadThumbnail()
        }
        .onReceive(NotificationCenter.default.publisher(for: .captureDidComplete)) { _ in
            Task {
                await loadThumbnail()
            }
        }
    }
    
    private func loadThumbnail() async {
        let image = await PhotoLibrarySaver.shared.fetchLastThumbnail(targetSize: CGSize(width: 100, height: 100))
        await MainActor.run {
            self.thumbnail = image
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        GalleryThumbnailView(onTap: {})
    }
}
