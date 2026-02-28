import AVFoundation
import UIKit

class CameraService: NSObject {
    private let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var continuation: CheckedContinuation<Data, Error>?

    var previewLayer: AVCaptureVideoPreviewLayer {
        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        return layer
    }

    var isRunning: Bool {
        captureSession.isRunning
    }

    func configure() throws {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .photo

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            captureSession.commitConfiguration()
            throw CameraError.noCameraAvailable
        }

        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
        }

        captureSession.commitConfiguration()
    }

    func start() {
        let session = captureSession
        Task.detached {
            session.startRunning()
        }
    }

    func stop() {
        let session = captureSession
        Task.detached {
            session.stopRunning()
        }
    }

    func capturePhoto() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let settings = AVCapturePhotoSettings()
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
}

extension CameraService: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        Task { @MainActor in
            if let error {
                self.continuation?.resume(throwing: error)
                self.continuation = nil
                return
            }
            guard let data = photo.fileDataRepresentation() else {
                self.continuation?.resume(throwing: CameraError.captureError)
                self.continuation = nil
                return
            }
            self.continuation?.resume(returning: data)
            self.continuation = nil
        }
    }
}

enum CameraError: LocalizedError {
    case noCameraAvailable
    case captureError

    var errorDescription: String? {
        switch self {
        case .noCameraAvailable: return "No camera available"
        case .captureError: return "Failed to capture photo"
        }
    }
}
