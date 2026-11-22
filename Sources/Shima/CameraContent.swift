import SwiftUI
import ShimaCore

/// The Camera tab as drawn in mockup/index.html: the preview on the left; Live, Mirror, Switch camera, Close and a note on the right.
struct CameraContent: View {
    let service: CameraService
    let state: AppState

    var body: some View {
        let preview = NowPlayingLayout.cameraPreview
        ZStack(alignment: .topLeading) {
            previewPane
                .frame(width: preview.width, height: preview.height)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .position(x: preview.midX, y: preview.midY)
            live
                .frame(width: NowPlayingLayout.cameraLive.width, height: NowPlayingLayout.cameraLive.height, alignment: .leading)
                .position(x: NowPlayingLayout.cameraLive.midX, y: NowPlayingLayout.cameraLive.midY)
            tile(NowPlayingLayout.cameraMirror, "Mirror", service.mirrored ? "On" : "Off") {
                service.mirrored.toggle()
                Log.camera.info("camera mirror=\(service.mirrored, privacy: .public)")
            }
            .accessibilityLabel("Mirror preview")
            .accessibilityValue(service.mirrored ? "On" : "Off")
            tile(NowPlayingLayout.cameraSwitch, "Switch camera", service.cameraName.replacingOccurrences(of: " Camera", with: "")) { service.switchCamera() }
                .disabled(!service.canSwitchCamera)
                .opacity(service.canSwitchCamera ? 1 : 0.45)
            tile(NowPlayingLayout.cameraClose, "Close", nil) { state.selectedTab = .music }
            Text("Camera is off when this closes")
                .font(.system(size: 9.5)).foregroundStyle(Color.white.opacity(0.52)).multilineTextAlignment(.center)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                .frame(width: NowPlayingLayout.cameraNote.width, height: NowPlayingLayout.cameraNote.height)
                .position(x: NowPlayingLayout.cameraNote.midX, y: NowPlayingLayout.cameraNote.midY)
        }
        .foregroundStyle(.white)
        .frame(width: IslandLayout.expanded.width, height: IslandLayout.expanded.height, alignment: .topLeading)
        .onAppear { service.refreshCameras() }
    }

    @ViewBuilder private var previewPane: some View {
        if service.coordinator.model.permission == .denied {
            VStack(spacing: 8) {
                Text("Camera access is off.").font(.system(size: 13))
                Button("Open Camera Settings") { service.openPrivacySettings() }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.white.opacity(0.15), in: Capsule())
            }
        } else if let failure = service.capture?.failure {
            Text(failure).font(.system(size: 12)).multilineTextAlignment(.center).padding()
        } else if let capture = service.capture {
            CameraPreview(client: capture, mirrored: service.mirrored)
        } else {
            LinearGradient(colors: [.indigo, .teal], startPoint: service.mirrored ? .topTrailing : .topLeading,
                           endPoint: service.mirrored ? .bottomLeading : .bottomTrailing)
        }
    }

    @ViewBuilder private var live: some View {
        if service.coordinator.model.permission != .denied && service.capture?.failure == nil {
            HStack(spacing: 6) {
                Circle().fill(Color(red: 1, green: 0.27, blue: 0.23)).frame(width: 7, height: 7)
                Text("Live").font(.system(size: 11))
            }
        }
    }

    private func tile(_ r: CGRect, _ title: String, _ sub: String?, action: @escaping @MainActor () -> Void) -> some View {
        Button { action() } label: {
            VStack(spacing: 1) {
                Text(title).font(.system(size: 11.5, weight: .semibold))
                if let sub { Text(sub).font(.system(size: 9.5)).foregroundStyle(Color.white.opacity(0.52)).lineLimit(1) }
            }
            .frame(width: r.width, height: r.height)
            .background(RoundedRectangle(cornerRadius: 11).fill(Color.white.opacity(0.075)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .position(x: r.midX, y: r.midY)
    }
}
