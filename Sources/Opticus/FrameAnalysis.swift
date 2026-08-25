import AppKit
import CoreML
import CoreImage
import Vision

struct OwnerFacePrints: @unchecked Sendable {
    let values: [VNFeaturePrintObservation]
}

struct NormalizedPoint: Sendable {
    var x: Double
    var y: Double
}

struct NormalizedRect: Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

struct FaceCandidateAnalysis: Sendable {
    var faceRect: NormalizedRect
    var contour: [NormalizedPoint]
    var ownerDistance: Double?
    var isSelected: Bool
}

struct FrameAnalysis: @unchecked Sendable {
    var imageWidth: Int
    var imageHeight: Int
    var faceRect: NormalizedRect?
    var landmarks: [NormalizedPoint]
    var faceContours: [[NormalizedPoint]]
    var regions: [NormalizedRect]
    var vector: VisionVector?
    var neuralGlassesProbability: Double?
    var facePrint: VNFeaturePrintObservation?
    var yaw: Double
    var roll: Double
    var pitch: Double
    var pitchSignal: Double?
    var faceWidth: Double
    var foreignFaceDetected: Bool
    var faceCandidates: [FaceCandidateAnalysis]
}

final class FrameAnalyzer: @unchecked Sendable {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let landmarksRequest = VNDetectFaceLandmarksRequest()
    private let rectanglesRequest = VNDetectFaceRectanglesRequest()
    private let eyeglassesRequest: VNCoreMLRequest?
    private var cachedSingleFacePrint: VNFeaturePrintObservation?
    private var cachedSingleOwnerDistance: Float?
    private var cachedSingleFaceRect: CGRect?
    private var lastOwnerEvaluation = 0.0

    init() {
        guard let url = Bundle.main.url(
            forResource: "EyeglassesClassifier", withExtension: "mlmodelc"
        ) ?? Bundle.module.url(
            forResource: "EyeglassesClassifier", withExtension: "mlmodelc"
        ) else {
            eyeglassesRequest = nil
            return
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        guard let model = try? MLModel(contentsOf: url, configuration: configuration),
              let visionModel = try? VNCoreMLModel(for: model) else {
            eyeglassesRequest = nil
            return
        }
        let coreMLRequest = VNCoreMLRequest(model: visionModel)
        coreMLRequest.imageCropAndScaleOption = .scaleFill
        eyeglassesRequest = coreMLRequest
    }

    func analyze(
        pixelBuffer: CVPixelBuffer,
        ownerFacePrints: OwnerFacePrints = OwnerFacePrints(values: []),
        needsLandmarks: Bool = true,
        captureOwnerFacePrint: Bool = false
    ) throws -> FrameAnalysis {
        // macOS camera buffers are already landscape-up. Mirror horizontally for
        // the familiar selfie view; rotating left here turns the preview sideways.
        let oriented = CIImage(cvPixelBuffer: pixelBuffer).oriented(.upMirrored)
        let imageWidth = Int(oriented.extent.width)
        let imageHeight = Int(oriented.extent.height)
        let handler = VNImageRequestHandler(ciImage: oriented)
        let faces: [VNFaceObservation]
        if needsLandmarks {
            try handler.perform([landmarksRequest])
            faces = landmarksRequest.results ?? []
        } else {
            try handler.perform([rectanglesRequest])
            faces = rectanglesRequest.results ?? []
        }
        guard !faces.isEmpty else {
            clearCachedOwner()
            return FrameAnalysis(
                imageWidth: imageWidth, imageHeight: imageHeight,
                faceRect: nil, landmarks: [], faceContours: [], regions: [],
                vector: nil, neuralGlassesProbability: nil,
                facePrint: nil,
                yaw: 0, roll: 0, pitch: 0, pitchSignal: nil,
                faceWidth: 0, foreignFaceDetected: false,
                faceCandidates: []
            )
        }

        var prints: [Int: VNFeaturePrintObservation] = [:]
        var ownerDistances: [Int: Float] = [:]
        if !ownerFacePrints.values.isEmpty {
            if faces.count == 1, canReuseOwner(for: faces[0].boundingBox),
               let cachedSingleFacePrint, let cachedSingleOwnerDistance {
                prints[0] = cachedSingleFacePrint
                ownerDistances[0] = cachedSingleOwnerDistance
            } else {
                for (index, face) in faces.enumerated() {
                    guard let print = generateFacePrint(handler: handler, faceRect: face.boundingBox),
                          let distance = closestDistance(from: print, to: ownerFacePrints.values) else { continue }
                    prints[index] = print
                    ownerDistances[index] = distance
                }
                if faces.count == 1, let print = prints[0], let distance = ownerDistances[0] {
                    cachedSingleFacePrint = print
                    cachedSingleOwnerDistance = distance
                    cachedSingleFaceRect = faces[0].boundingBox
                    lastOwnerEvaluation = ProcessInfo.processInfo.systemUptime
                } else {
                    clearCachedOwner()
                }
            }
        }
        let selectedIndex = ownerDistances.min(by: { $0.value < $1.value })?.key
            ?? faces.indices.max(by: { faces[$0].boundingBox.width < faces[$1].boundingBox.width })!
        let face = faces[selectedIndex]
        let facePrint = prints[selectedIndex] ?? (captureOwnerFacePrint
            ? generateFacePrint(handler: handler, faceRect: face.boundingBox)
            : nil)
        let candidates = faces.enumerated().map { index, candidate in
            FaceCandidateAnalysis(
                faceRect: NormalizedRect(candidate.boundingBox),
                contour: faceLandmarkContours(candidate).first ?? [],
                ownerDistance: ownerDistances[index].map(Double.init),
                isSelected: index == selectedIndex
            )
        }

        let faceRect = NormalizedRect(face.boundingBox)
        let landmarkPoints = allLandmarkPoints(face).map { point in
            NormalizedPoint(
                x: face.boundingBox.minX + Double(point.x) * face.boundingBox.width,
                y: face.boundingBox.minY + Double(point.y) * face.boundingBox.height
            )
        }
        let contours = faceLandmarkContours(face)
        let regions = featureRegions(face: faceRect)
        let featureScale = min(1, 320 / max(oriented.extent.width, 1))
        let featureImage = oriented.transformed(
            by: CGAffineTransform(scaleX: featureScale, y: featureScale)
        )
        guard let vectorImage = context.createCGImage(featureImage, from: featureImage.extent) else {
            throw AnalysisError.imageConversion
        }
        let vector = extractVector(image: vectorImage, regions: regions)
        let neuralProbability = predictEyeglasses(handler: handler, faceRect: face.boundingBox)
        return FrameAnalysis(
            imageWidth: imageWidth, imageHeight: imageHeight,
            faceRect: faceRect, landmarks: landmarkPoints,
            faceContours: contours, regions: regions, vector: vector,
            neuralGlassesProbability: neuralProbability,
            facePrint: facePrint,
            yaw: face.yaw?.doubleValue ?? 0,
            roll: face.roll?.doubleValue ?? 0,
            pitch: face.pitch?.doubleValue ?? 0,
            pitchSignal: landmarkPitchSignal(face),
            faceWidth: face.boundingBox.width,
            foreignFaceDetected: ownerDistances[selectedIndex].map {
                $0 >= RecognitionSignal.ownerMatchThreshold
            } ?? false,
            faceCandidates: candidates
        )
    }

    private func canReuseOwner(for rect: CGRect) -> Bool {
        guard let cachedSingleFaceRect,
              ProcessInfo.processInfo.systemUptime - lastOwnerEvaluation < 0.4 else { return false }
        let centerDelta = hypot(rect.midX - cachedSingleFaceRect.midX, rect.midY - cachedSingleFaceRect.midY)
        let sizeRatio = rect.width / max(cachedSingleFaceRect.width, 0.001)
        return centerDelta < max(rect.width, cachedSingleFaceRect.width) * 0.28
            && sizeRatio > 0.72 && sizeRatio < 1.38
    }

    private func clearCachedOwner() {
        cachedSingleFacePrint = nil
        cachedSingleOwnerDistance = nil
        cachedSingleFaceRect = nil
        lastOwnerEvaluation = 0
    }

    private func closestDistance(
        from facePrint: VNFeaturePrintObservation,
        to references: [VNFeaturePrintObservation]
    ) -> Float? {
        references.compactMap { reference -> Float? in
            var distance: Float = 0
            guard (try? facePrint.computeDistance(&distance, to: reference)) != nil else { return nil }
            return distance
        }.min()
    }

    private func generateFacePrint(
        handler: VNImageRequestHandler,
        faceRect: CGRect
    ) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()
        request.revision = VNGenerateImageFeaturePrintRequestRevision2
        request.regionOfInterest = faceRect
        request.imageCropAndScaleOption = .scaleFill
        guard (try? handler.perform([request])) != nil else { return nil }
        return request.results?.first
    }

    private func faceLandmarkContours(_ face: VNFaceObservation) -> [[NormalizedPoint]] {
        guard let landmarks = face.landmarks else { return [] }
        return [
            landmarks.faceContour, landmarks.leftEye, landmarks.rightEye,
            landmarks.leftEyebrow, landmarks.rightEyebrow,
            landmarks.noseCrest, landmarks.nose, landmarks.outerLips, landmarks.innerLips,
        ]
        .compactMap { $0 }
        .map { region in
            (0..<region.pointCount).map { index in
                let point = region.normalizedPoints[index]
                return NormalizedPoint(
                    x: face.boundingBox.minX + Double(point.x) * face.boundingBox.width,
                    y: face.boundingBox.minY + Double(point.y) * face.boundingBox.height
                )
            }
        }
    }

    private func landmarkPitchSignal(_ face: VNFaceObservation) -> Double? {
        guard let landmarks = face.landmarks,
              let leftEye = landmarks.leftEye,
              let rightEye = landmarks.rightEye,
              let nose = landmarks.nose,
              let lips = landmarks.outerLips else { return nil }

        func centerY(_ region: VNFaceLandmarkRegion2D) -> Double {
            guard region.pointCount > 0 else { return 0 }
            return (0..<region.pointCount).reduce(0) {
                $0 + Double(region.normalizedPoints[$1].y)
            } / Double(region.pointCount)
        }

        let eyesY = (centerY(leftEye) + centerY(rightEye)) / 2
        let noseY = centerY(nose)
        let mouthY = centerY(lips)
        let eyeToMouth = eyesY - mouthY
        guard abs(eyeToMouth) > 0.04 else { return nil }
        return (eyesY - noseY) / eyeToMouth
    }

    private func predictEyeglasses(
        handler: VNImageRequestHandler,
        faceRect: CGRect
    ) -> Double? {
        guard let eyeglassesRequest else { return nil }
        let expanded = faceRect.insetBy(dx: -faceRect.width * 0.08, dy: -faceRect.height * 0.08)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !expanded.isNull, expanded.width > 0, expanded.height > 0 else { return nil }
        eyeglassesRequest.regionOfInterest = expanded
        guard (try? handler.perform([eyeglassesRequest])) != nil,
              let observation = eyeglassesRequest.results?.first as? VNCoreMLFeatureValueObservation,
              let value = observation.featureValue.multiArrayValue?[0] else { return nil }
        return max(0, min(1, value.doubleValue))
    }

    private func allLandmarkPoints(_ face: VNFaceObservation) -> [CGPoint] {
        guard let landmarks = face.landmarks else { return [] }
        return [landmarks.leftEye, landmarks.rightEye, landmarks.leftEyebrow,
                landmarks.rightEyebrow, landmarks.nose, landmarks.outerLips]
            .compactMap { $0 }
            .flatMap { region in (0..<region.pointCount).map { region.normalizedPoints[$0] } }
    }

    private func featureRegions(face: NormalizedRect) -> [NormalizedRect] {
        func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> NormalizedRect {
            NormalizedRect(
                x: face.x + x * face.width, y: face.y + y * face.height,
                width: w * face.width, height: h * face.height
            )
        }
        return [
            rect(0.12, 0.50, 0.34, 0.24),
            rect(0.54, 0.50, 0.34, 0.24),
            rect(0.42, 0.43, 0.16, 0.34),
            rect(0.18, 0.20, 0.25, 0.18),
            rect(0.57, 0.20, 0.25, 0.18),
        ]
    }

    private func extractVector(
        image: CGImage,
        regions: [NormalizedRect]
    ) -> VisionVector? {
        let width = 320
        let height = max(1, Int(Double(width) * Double(image.height) / Double(image.width)))
        let rowBytes = width * 4
        var pixels = [UInt8](repeating: 0, count: rowBytes * height)
        guard let bitmap = CGContext(
            data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: rowBytes,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return nil }
        bitmap.interpolationQuality = .medium
        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        return pixels.withUnsafeBufferPointer { pointer in
            func luminance(_ x: Int, _ y: Int) -> Double {
                let clampedX = max(0, min(width - 1, x))
                let clampedY = max(0, min(height - 1, y))
                let offset = clampedY * rowBytes + clampedX * 4
                return (0.2126 * Double(pointer[offset]) + 0.7152 * Double(pointer[offset + 1]) + 0.0722 * Double(pointer[offset + 2])) / 255
            }

            func metrics(_ rect: NormalizedRect) -> (edge: Double, mean: Double) {
                let minX = max(1, Int(rect.x * Double(width)))
                let maxX = min(width - 2, Int((rect.x + rect.width) * Double(width)))
                // Vision's origin is bottom-left; bitmap rows start at bottom-left here.
                let minY = max(1, Int(rect.y * Double(height)))
                let maxY = min(height - 2, Int((rect.y + rect.height) * Double(height)))
                guard minX < maxX, minY < maxY else { return (0, 0) }
                var edge = 0.0
                var mean = 0.0
                var count = 0
                for y in minY...maxY {
                    for x in minX...maxX {
                        let center = luminance(x, y)
                        edge += abs(luminance(x + 1, y) - luminance(x - 1, y))
                        edge += abs(luminance(x, y + 1) - luminance(x, y - 1))
                        mean += center
                        count += 1
                    }
                }
                return (edge / Double(max(count, 1)), mean / Double(max(count, 1)))
            }

            let measurements = regions.map(metrics)
            guard measurements.count == 5 else { return nil }
            let leftEye = measurements[0]
            let rightEye = measurements[1]
            let bridge = measurements[2]
            let leftCheek = measurements[3]
            let rightCheek = measurements[4]
            let symmetry = 1 - min(1, abs(leftEye.edge - rightEye.edge) / max(leftEye.edge + rightEye.edge, 0.001))
            return VisionVector([
                leftEye.edge, rightEye.edge, bridge.edge,
                abs(leftEye.mean - leftCheek.mean), abs(rightEye.mean - rightCheek.mean), symmetry,
            ])
        }
    }
}

final class PreviewRenderer: @unchecked Sendable {
    private let context = CIContext(options: [.cacheIntermediates: false])

    func render(pixelBuffer: CVPixelBuffer) -> CGImage? {
        let image = CIImage(cvPixelBuffer: pixelBuffer).oriented(.upMirrored)
        let scale = min(1, 960 / max(image.extent.width, 1))
        let preview = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return context.createCGImage(preview, from: preview.extent)
    }
}

private extension NormalizedRect {
    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.width
        height = rect.height
    }
}

enum AnalysisError: Error {
    case imageConversion
}
