import SwiftUI
import AVFoundation
import UIKit

/// Live rear-camera capture for the dish scanner.
///
/// The Simulator has no capture device, so `status` reports `.unavailable` there and the
/// scan screen falls back to the photo picker instead of showing a dead black rectangle.
@MainActor
final class CameraController: NSObject, ObservableObject {
    enum Status: Equatable {
        case idle          // not started yet
        case unavailable   // no camera hardware (Simulator, iPod, etc.)
        case denied        // user said no in Settings
        case running       // preview is live
    }

    @Published private(set) var status: Status = .idle
    /// Set to true between the shutter tap and the image arriving.
    @Published private(set) var capturing = false

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var configured = false
    private var onCapture: ((UIImage?) -> Void)?
    private let sessionQueue = DispatchQueue(label: "com.goodies.goodiesSnap.camera")

    // MARK: - Lifecycle

    func start() async {
        guard status != .running else { return }

        guard AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil else {
            status = .unavailable
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                status = .denied
                return
            }
        default:
            status = .denied
            return
        }

        guard configure() else {
            status = .unavailable
            return
        }

        let session = self.session
        sessionQueue.async {
            if !session.isRunning { session.startRunning() }
        }
        status = .running
    }

    func stop() {
        let session = self.session
        sessionQueue.async {
            if session.isRunning { session.stopRunning() }
        }
        if status == .running { status = .idle }
    }

    /// Builds the capture graph once; returns false if the device refuses to attach.
    private func configure() -> Bool {
        if configured { return true }

        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input),
              session.canAddOutput(output) else {
            session.commitConfiguration()
            return false
        }

        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()
        configured = true
        return true
    }

    // MARK: - Capture

    /// Fires the shutter. `completion` gets the still, or nil if the capture failed.
    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        guard status == .running, !capturing else {
            completion(nil)
            return
        }
        capturing = true
        onCapture = completion

        let settings = AVCapturePhotoSettings()
        // Portrait-locked app: keep the still upright regardless of how the device is held.
        if let connection = output.connection(with: .video) {
            if #available(iOS 17.0, *) {
                if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            } else if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
        }
        output.capturePhoto(with: settings, delegate: self)
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let image = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.capturing = false
            let handler = self.onCapture
            self.onCapture = nil
            handler?(error == nil ? image : nil)
        }
    }
}

// MARK: - Preview layer

/// Hosts the `AVCaptureVideoPreviewLayer` so SwiftUI can show the live feed.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.backgroundColor = .black
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if uiView.videoPreviewLayer.session !== session {
            uiView.videoPreviewLayer.session = session
        }
    }

    /// A UIView whose backing layer *is* the preview layer, so it resizes without manual frame math.
    final class PreviewView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
