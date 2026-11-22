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
    private(set) var deviceName = "Camera"
    private(set) var canSwitch = false
    @ObservationIgnored private var selectedID: String?
    @ObservationIgnored private let worker = CameraCaptureWorker()
    @ObservationIgnored private var generation = 0
    @ObservationIgnored fileprivate let previewLayer: AVCaptureVideoPreviewLayer

    init() {
        // Bind before any queue work can begin. Mounting/removing the SwiftUI
        // preview never mutates session connections during configuration.
        previewLayer = AVCaptureVideoPreviewLayer(session: worker.session)
        previewLayer.videoGravity = .resizeAspectFill
    }

    /// Reads the device list (cheap, no capture session involved); called when the Camera tab appears.
    func refreshDevices() {
        let list = Self.videoDevices()
        canSwitch = list.count > 1
        let current = selectedID.flatMap { id in list.first { $0.uniqueID == id } }
            ?? AVCaptureDevice.default(for: .video) ?? list.first
        deviceName = current?.localizedName ?? "Camera"
    }

    /// Moves to the next camera; a running session swaps its input without stopping.
    func switchDevice() {
        let list = Self.videoDevices()
        guard list.count > 1 else { return }
        let currentID = selectedID ?? AVCaptureDevice.default(for: .video)?.uniqueID
        let index = list.firstIndex { $0.uniqueID == currentID } ?? -1
        let next = list[(index + 1) % list.count]
        selectedID = next.uniqueID
        worker.select(deviceID: next.uniqueID)
        refreshDevices()
    }

    private static func videoDevices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                                         mediaType: .video, position: .unspecified).devices
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

    /// Reply to AppKit termination only after the capture queue has drained.
    /// The main actor remains available while a device is starting or stopping.
    func stop(completion: @escaping @MainActor () -> Void) {
        generation += 1
        worker.stop { [self] in
            // AppKit waits in a nested modal loop for terminateLater. A main-queue
            // Task cannot run if terminate was called from that queue's callback.
            RunLoop.main.perform(inModes: [.common, .modalPanel, .eventTracking]) {
                MainActor.assumeIsolated {
                    self.active = false
                    completion()
                }
            }
        }
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

/// All mutable capture operations and the failure callback belong to `queue`. The session is
/// also handed to AVFoundation's preview layer on the main actor; that framework
/// reference does not configure, start or stop the session. No frame data crosses actors.
private final class CameraCaptureWorker: @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "local.shima.camera", qos: .userInitiated)
    private var failureHandler: (@Sendable (Result<Bool, CameraCaptureFailure>) -> Void)?
    private var observers: [NSObjectProtocol] = []
    private let intentLock = NSLock()
    private var wantsRunning = false
    // The epoch describes the run executing on the capture queue, rather than
    // the latest UI intent (which may already refer to a future queued start).
    private var nextRunEpoch: UInt64 = 0 // capture queue only
    private var preferredID: String? // capture queue only
    private var activeRunEpoch: UInt64? // protected by intentLock

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification,
                                             object: session, queue: nil) { [weak self] _ in
            self?.captureFailed(deviceID: nil)
        })
        observers.append(center.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification,
                                             object: nil, queue: nil) { [weak self] note in
            guard let deviceID = (note.object as? AVCaptureDevice)?.uniqueID else { return }
            self?.captureFailed(deviceID: deviceID)
        })
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

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
            nextRunEpoch &+= 1
            let runEpoch = nextRunEpoch
            intentLock.withLock { activeRunEpoch = runEpoch }
            failureHandler = completion
            if session.inputs.isEmpty {
                guard let device = preferredID.flatMap({ AVCaptureDevice(uniqueID: $0) }) ?? AVCaptureDevice.default(for: .video) else {
                    stop()
                    completion(.failure(.unavailable))
                    return
                }
                do {
                    let input = try AVCaptureDeviceInput(device: device)
                    session.beginConfiguration()
                    guard session.canAddInput(input) else {
                        session.commitConfiguration()
                        stop()
                        completion(.failure(.configuration))
                        return
                    }
                    session.addInput(input)
                    session.commitConfiguration()
                } catch {
                    stop()
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
            if session.isRunning {
                completion(.success(true))
            } else {
                stop()
                completion(.failure(.configuration))
            }
        }
    }

    /// Remembers the chosen camera and, when a session already has an input, swaps it in place.
    func select(deviceID: String) {
        queue.async { [self] in
            preferredID = deviceID
            guard !session.inputs.isEmpty, let device = AVCaptureDevice(uniqueID: deviceID),
                  let input = try? AVCaptureDeviceInput(device: device) else { return }
            session.beginConfiguration()
            for existing in session.inputs { session.removeInput(existing) }
            if session.canAddInput(input) { session.addInput(input) }
            session.commitConfiguration()
        }
    }

    func stop(completion: @escaping @Sendable () -> Void) {
        intentLock.withLock { wantsRunning = false }
        queue.async { [self] in
            stop()
            completion()
        }
    }

    private func captureFailed(deviceID: String?) {
        // Snapshot at notification delivery, before hopping to the queue. A
        // stop/reopen already queued ahead of this callback must invalidate it.
        guard let reportedEpoch = intentLock.withLock({ activeRunEpoch }) else { return }
        queue.async { [self] in
            guard intentLock.withLock({ activeRunEpoch == reportedEpoch }) else { return }
            guard let handler = failureHandler else { return }
            if let deviceID {
                guard session.inputs.contains(where: { ($0 as? AVCaptureDeviceInput)?.device.uniqueID == deviceID }) else { return }
            }
            stop()
            handler(.failure(deviceID == nil ? .configuration : .unavailable))
        }
    }

    private func stop() {
        intentLock.withLock { activeRunEpoch = nil }
        if session.isRunning {
            session.stopRunning()
            Log.camera.info("camera session stop fake=false")
        }
        // Resolve the system default afresh on the next eligible opening. A stale
        // disconnected input must never prevent recovery after reconnection.
        if !session.inputs.isEmpty {
            session.beginConfiguration()
            for input in session.inputs { session.removeInput(input) }
            session.commitConfiguration()
        }
        failureHandler = nil
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
        view.detachPreview()
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
        guard ownsPreview else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        preview.frame = bounds
        CATransaction.commit()
    }

    private var ownsPreview: Bool { preview.superlayer === layer }

    func detachPreview() {
        guard ownsPreview else { return }
        preview.removeFromSuperlayer()
    }

    func setMirrored(_ mirrored: Bool) {
        guard ownsPreview, let connection = preview.connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = mirrored
    }
}
