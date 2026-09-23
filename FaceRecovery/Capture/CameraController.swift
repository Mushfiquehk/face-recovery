// AVCaptureSession and friends are not Sendable, but driving them from a dedicated serial
// queue is Apple's own prescribed pattern and is safe. The import annotation keeps that
// deliberate hop from generating noise on every build.
@preconcurrency import AVFoundation
import UIKit

/// Front-camera session for taking a Face Scan.
///
/// The capture protocol matters more than anything in the prompt: lighting is the dominant
/// confound, so the framing guide and a fixed time and place are what make scans comparable.
@MainActor
@Observable
final class CameraController: NSObject {
    enum Status {
        case idle
        case denied
        case failed(String)
        case running
    }

    private(set) var status: Status = .idle

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.mushfique.facerecovery.camera")
    private var captureContinuation: CheckedContinuation<UIImage, Error>?

    func start() async {
        guard case .idle = status else {
            if case .running = status { resumeSession() }
            return
        }

        guard await requestAccess() else {
            status = .denied
            return
        }

        do {
            try configureSession()
            status = .running
            resumeSession()
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    func capture() async throws -> UIImage {
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        return try await withCheckedThrowingContinuation { continuation in
            captureContinuation = continuation
            sessionQueue.async { [output] in
                output.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    private func resumeSession() {
        sessionQueue.async { [session] in
            if !session.isRunning { session.startRunning() }
        }
    }

    private func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .video)
        default: false
        }
    }

    private func configureSession() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .front
        ) else {
            throw CaptureError.noFrontCamera
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw CaptureError.configurationFailed
        }
        session.addInput(input)
        session.addOutput(output)
    }

    enum CaptureError: LocalizedError {
        case noFrontCamera
        case configurationFailed
        case noImageData

        var errorDescription: String? {
            switch self {
            case .noFrontCamera: "No front camera is available on this device."
            case .configurationFailed: "The camera could not be configured."
            case .noImageData: "The photo could not be read from the camera."
            }
        }
    }
}

extension CameraController: @preconcurrency AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let continuation = captureContinuation
        captureContinuation = nil

        if let error {
            continuation?.resume(throwing: error)
        } else if let data = photo.fileDataRepresentation(), let image = UIImage(data: data) {
            continuation?.resume(returning: image)
        } else {
            continuation?.resume(throwing: CaptureError.noImageData)
        }
    }
}
