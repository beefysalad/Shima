import SwiftUI
import ShimaCore

struct CameraContent: View {
    let service: CameraService

    var body: some View {
        let rect = NowPlayingLayout.cameraPreview
        ZStack(alignment: .topLeading) {
            ZStack(alignment: .bottomTrailing) {
                if service.coordinator.model.permission == .denied {
                    VStack(spacing: 8) {
                        Text("Camera access is off.").font(.system(size: 13))
                        Button("Open Camera Settings") { service.openPrivacySettings() }
                            .buttonStyle(.plain).font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.white.opacity(0.15), in: Capsule())
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let failure = service.capture?.failure {
                    Text(failure).font(.system(size: 12)).multilineTextAlignment(.center)
                        .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    if let capture = service.capture {
                        CameraPreview(client: capture, mirrored: service.mirrored)
                    } else {
                        LinearGradient(colors: [.indigo, .teal], startPoint: service.mirrored ? .topTrailing : .topLeading, endPoint: service.mirrored ? .bottomLeading : .bottomTrailing)
                    }
                    Button {
                        service.mirrored.toggle()
                        Log.camera.info("camera mirror=\(service.mirrored, privacy: .public)")
                    } label: {
                        Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                            .font(.system(size: 12)).frame(width: 28, height: 28)
                            .background(.black.opacity(0.75), in: Circle())
                    }
                    .buttonStyle(.plain).padding(8)
                    .accessibilityLabel("Mirror preview")
                    .accessibilityValue(service.mirrored ? "On" : "Off")
                }
            }
            .foregroundStyle(.white)
            .frame(width: rect.width, height: rect.height)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .position(x: rect.midX, y: rect.midY)
        }
        .frame(width: IslandLayout.expanded.width, height: IslandLayout.expanded.height, alignment: .topLeading)
    }
}
