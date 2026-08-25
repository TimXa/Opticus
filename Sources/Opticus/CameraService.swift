@preconcurrency import AVFoundation
import CoreMedia
import Foundation

final class CameraService: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "app.opticus.camera.session")
    private let frameQueue = DispatchQueue(label: "app.opticus.camera.frames", qos: .userInitiated)
    private var lastFrameTime = 0.0
    var onFrame: (@Sendable (SendablePixelBuffer) -> Void)?

    func start() async throws {
        let permitted: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permitted = true
        case .notDetermined:
            permitted = await AVCaptureDevice.requestAccess(for: .video)
        default:
            permitted = false
        }
        guard permitted else { throw CameraError.permissionDenied }
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [self] in
                do {
                    try configureIfNeeded()
                    session.startRunning()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configureIfNeeded() throws {
        guard session.inputs.isEmpty else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .high

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(for: .video) else {
            throw CameraError.noCamera
        }
        let input = try AVCaptureDeviceInput(device: camera)
        guard session.canAddInput(input) else { throw CameraError.configuration }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        let preferredPixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        let pixelFormat = output.availableVideoPixelFormatTypes.contains(preferredPixelFormat)
            ? preferredPixelFormat
            : kCVPixelFormatType_32BGRA
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
        ]
        output.setSampleBufferDelegate(self, queue: frameQueue)
        guard session.canAddOutput(output) else { throw CameraError.configuration }
        session.addOutput(output)
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = CACurrentMediaTime()
        guard now - lastFrameTime >= 1.0 / 30.0,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrameTime = now
        onFrame?(SendablePixelBuffer(value: pixelBuffer))
    }
}

// The capture output owns the buffer until this callback returns; Core Video buffers
// are reference-counted and safe to retain while the analyzer reads them.
struct SendablePixelBuffer: @unchecked Sendable {
    let value: CVPixelBuffer
}

enum CameraError: LocalizedError {
    case permissionDenied
    case noCamera
    case configuration

    var errorDescription: String? {
        switch self {
        case .permissionDenied: "Нет доступа к камере. Разрешите его в Системных настройках → Конфиденциальность и безопасность → Камера."
        case .noCamera: "Камера не найдена."
        case .configuration: "Не удалось настроить камеру."
        }
    }
}
