import AppKit
import AVFoundation
import Observation
import ShimaCore
import SwiftUI

/// The main actor publishes UI state; the worker alone configures and runs capture.
@Observable @MainActor
final class CameraCaptureClient: CameraClient {
    private(set) var failure: String?
    private(set) var active = false
    @ObservationIgnored private let worker = CameraCaptureWorker()
    @ObservationIgnored private var generation = 0
    @ObservationIgnored fileprivate let previewLayer: AVCaptureVideoPreviewLayer

    init() {
        // Bind before any queue work can begin. Mounting/removing the SwiftUI
        // preview never mutates session connections during configuration.
        previewLayer = AVCaptureVideoPreviewLayer(session: worker.session)
        previewLayer.videoGravity = .resizeAspectFill
    }

    var permission: CameraPermission {
        Self.permission(AVCaptureDevice.authorizationStatus(for: .video))
    }

    func requestPermission(_ completion: @escaping @MainActor (CameraPermission) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            Task { @MainActor in completion(granted ? .authorized : .denied) }
        }
    }

    func setRunning(_ running: Bool) {
        generation += 1
        let ticket = generation
        if running { failure = nil }
        worker.setRunning(running) { [weak self] result in
            Task { @MainActor in
                guard let self, self.generation == ticket else { return }
                switch result {
                case .success(let active): self.active = active
                case .failure(let error):
                    self.active = false
                    self.failure = error.rawValue
                }
            }
        }
    }

    /// Termination waits for the serial queue to stop capture before the process exits.
    func stopAndWait() {
        generation += 1
        worker.stopAndWait()
        active = false
    }

    private static func permission(_ status: AVAuthorizationStatus) -> CameraPermission {
        switch status {
        case .notDetermined: .notDetermined
        case .authorized: .authorized
        case .denied, .restricted: .denied
        @unknown default: .denied
        }
    }
}

private enum CameraCaptureFailure: String, Error, Sendable {
    case permission = "Camera access is unavailable."
    case unavailable = "No camera is available."
    case configuration = "The camera could not be opened."
}

/// All mutable capture operations and `configured` belong to `queue`. The session is
/// also handed to AVFoundation's preview layer on the main actor; that framework
/// reference does not configure, start or stop the session. No frame data crosses actors.
private final class CameraCaptureWorker: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "local.shima.camera", qos: .userInitiated)
    private var configured = false
    private let intentLock = NSLock()
    private var wantsRunning = false

    func setRunning(_ running: Bool,
                    completion: @escaping @Sendable (Result<Bool, CameraCaptureFailure>) -> Void) {
        intentLock.withLock { wantsRunning = running }
        queue.async { [self] in
            if !running || !intentLock.withLock({ wantsRunning }) {
                stop()
                completion(.success(false))
                return
            }
            guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
                stop()
                completion(.failure(.permission))
                return
            }
            if !configured {
                guard let device = AVCaptureDevice.default(for: .video) else {
                    completion(.failure(.unavailable))
                    return
                }
                do {
                    let input = try AVCaptureDeviceInput(device: device)
                    session.beginConfiguration()
                    guard session.canAddInput(input) else {
                        session.commitConfiguration()
                        completion(.failure(.configuration))
                        return
                    }
                    session.addInput(input)
                    session.commitConfiguration()
                    configured = true
                } catch {
                    completion(.failure(.configuration))
                    return
                }
            }
            // A collapse can arrive while device configuration is in progress.
            guard intentLock.withLock({ wantsRunning }) else {
                stop()
                completion(.success(false))
                return
            }
            if !session.isRunning {
                session.startRunning()
                Log.camera.info("camera session start fake=false running=\(self.session.isRunning, privacy: .public)")
            }
            completion(session.isRunning ? .success(true) : .failure(.configuration))
        }
    }

    func stopAndWait() {
        intentLock.withLock { wantsRunning = false }
        queue.sync { stop() }
    }

    private func stop() {
        if session.isRunning {
            session.stopRunning()
            Log.camera.info("camera session stop fake=false")
        }
    }
}

struct CameraPreview: NSViewRepresentable {
    let client: CameraCaptureClient
    let mirrored: Bool

    func makeNSView(context: Context) -> CameraPreviewNSView {
        CameraPreviewNSView(preview: client.previewLayer)
    }

    func updateNSView(_ view: CameraPreviewNSView, context: Context) {
        // Reading active updates the connection after capture configuration finishes.
        _ = client.active
        view.setMirrored(mirrored)
    }

    static func dismantleNSView(_ view: CameraPreviewNSView, coordinator: ()) {
        view.preview.removeFromSuperlayer()
    }
}

final class CameraPreviewNSView: NSView {
    let preview: AVCaptureVideoPreviewLayer

    init(preview: AVCaptureVideoPreviewLayer) {
        self.preview = preview
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(preview)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        preview.frame = bounds
        CATransaction.commit()
    }

    func setMirrored(_ mirrored: Bool) {
        guard let connection = preview.connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = mirrored
    }
}
