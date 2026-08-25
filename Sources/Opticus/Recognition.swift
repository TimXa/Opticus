import Foundation

struct VisionVector: Codable, Equatable, Sendable {
    static let names = [
        "left eye edges", "right eye edges", "bridge edges",
        "left eye contrast", "right eye contrast", "frame symmetry",
    ]

    var values: [Double]

    init(_ values: [Double]) {
        precondition(values.count == Self.names.count)
        self.values = values
    }
}

struct CalibrationProfile: Codable, Equatable, Sendable {
    var withGlasses: [VisionVector]
    var withoutGlasses: [VisionVector]

    var isReady: Bool {
        withGlasses.count >= CalibrationPose.samplesPerClass
            && withoutGlasses.count >= CalibrationPose.samplesPerClass
    }

    func prediction(for vector: VisionVector) -> RawPrediction? {
        guard isReady else { return nil }
        let all = withGlasses + withoutGlasses
        let variance = (0..<VisionVector.names.count).map { index in
            let mean = all.map { $0.values[index] }.reduce(0, +) / Double(all.count)
            let sum = all.reduce(0) { $0 + pow($1.values[index] - mean, 2) }
            return max(sum / Double(all.count - 1), 0.000_025)
        }
        let glassesDistance = centroidDistance(vector, samples: withGlasses, variance: variance)
        let bareDistance = centroidDistance(vector, samples: withoutGlasses, variance: variance)
        // Normalize the margin so exposure changes cannot dominate tiny variances.
        let distanceSum = max(glassesDistance + bareDistance, 0.000_001)
        let relativeMargin = (bareDistance - glassesDistance) / distanceSum
        let logit = max(-8, min(8, relativeMargin * 8))
        return RawPrediction(
            glassesProbability: 1 / (1 + exp(-logit)),
            glassesDistance: glassesDistance,
            bareDistance: bareDistance
        )
    }

    private func centroidDistance(
        _ vector: VisionVector,
        samples: [VisionVector],
        variance: [Double]
    ) -> Double {
        let centroid = (0..<VisionVector.names.count).map { index in
            samples.map { $0.values[index] }.reduce(0, +) / Double(samples.count)
        }
        return zip(vector.values, centroid).enumerated().reduce(0) { result, item in
            let (index, pair) = item
            return result + pow(pair.0 - pair.1, 2) / variance[index]
        }.squareRoot()
    }
}

struct RawPrediction: Equatable, Sendable {
    var glassesProbability: Double
    var glassesDistance: Double
    var bareDistance: Double
}

enum RecognitionSignal {
    static let ownerMatchThreshold: Float = 0.85

    static func fused(neural: Double?, personal: Double?) -> Double? {
        switch (neural, personal) {
        // Calibration nudges the trained classifier; it never replaces it.
        case let (neural?, personal?): neural * 0.90 + personal * 0.10
        case let (neural?, nil): neural
        case let (nil, personal?): personal
        case (nil, nil): nil
        }
    }

}

enum GlassesState: String, Sendable {
    case unknown
    case withGlasses
    case withoutGlasses

    var title: String {
        switch self {
        case .unknown: "Распознаю…"
        case .withGlasses: "Очки надеты"
        case .withoutGlasses: "Без очков"
        }
    }
}

struct TemporalDecisionFilter: Sendable {
    static let glassesThreshold = 0.72
    static let bareThreshold = 0.28
    static let defaultDwell: TimeInterval = 0.55

    private(set) var rawProbability = 0.5
    private(set) var smoothedProbability = 0.5
    private(set) var state: GlassesState = .unknown
    private(set) var candidateState: GlassesState = .unknown
    private(set) var candidateProgress = 0.0
    private var candidateSince: TimeInterval = 0
    private var recentProbabilities: [Double] = []

    mutating func update(
        probability: Double,
        now: TimeInterval,
        dwell: TimeInterval = Self.defaultDwell
    ) -> GlassesState {
        rawProbability = max(0, min(1, probability))
        recentProbabilities.append(rawProbability)
        if recentProbabilities.count > 7 { recentProbabilities.removeFirst() }
        let sorted = recentProbabilities.sorted()
        let median = sorted[sorted.count / 2]
        smoothedProbability = smoothedProbability * 0.62 + median * 0.38
        let next: GlassesState
        if smoothedProbability >= Self.glassesThreshold {
            next = .withGlasses
        } else if smoothedProbability <= Self.bareThreshold {
            next = .withoutGlasses
        } else {
            next = state
        }

        if next != candidateState {
            candidateState = next
            candidateSince = now
        }
        guard candidateState != .unknown, candidateState != state else {
            candidateProgress = 0
            return state
        }

        candidateProgress = min(max((now - candidateSince) / dwell, 0), 1)
        if candidateProgress >= 1 {
            state = candidateState
            candidateProgress = 0
        }
        return state
    }

    mutating func reset() {
        self = TemporalDecisionFilter()
    }
}

enum CalibrationLabel: String, Codable, Sendable {
    case withGlasses
    case withoutGlasses

    var preparationTitle: String {
        self == .withGlasses ? "Наденьте очки" : "Снимите очки"
    }

    var preparationDetail: String {
        self == .withGlasses
            ? "Смотрите в камеру. Оправа и глаза должны быть хорошо видны."
            : "Уберите очки из кадра и смотрите в камеру."
    }
}

enum CalibrationStage: Equatable, Sendable {
    case preparation(CalibrationLabel)
    case scanning(CalibrationLabel)
    case success(CalibrationLabel)
}

enum CalibrationPose: String, CaseIterable, Sendable {
    case front, turnLeft, turnRight, tiltLeft, tiltRight, lookDown, closer, farther

    static let samplesPerPose = 3
    static var samplesPerClass: Int { allCases.count * samplesPerPose }

    var title: String {
        switch self {
        case .front: "Смотрите прямо в камеру"
        case .turnLeft: "Медленно поверните голову влево"
        case .turnRight: "Медленно поверните голову вправо"
        case .tiltLeft: "Наклоните голову к левому плечу"
        case .tiltRight: "Наклоните голову к правому плечу"
        case .lookDown: "Опустите подбородок и посмотрите исподлобья"
        case .closer: "Немного приблизьтесь к камере"
        case .farther: "Немного отодвиньтесь от камеры"
        }
    }

    func matches(
        yaw: Double, roll: Double, pitch: Double = 0,
        pitchSignal: Double? = nil, baselinePitchSignal: Double? = nil,
        faceWidth: Double, baselineWidth: Double?
    ) -> Bool {
        switch self {
        case .front:
            return abs(yaw) < 0.12 && abs(roll) < 0.10
        case .turnLeft:
            return yaw < -0.16
        case .turnRight:
            return yaw > 0.16
        case .tiltLeft:
            return roll > 0.15
        case .tiltRight:
            return roll < -0.15
        case .lookDown:
            let landmarkChange: Double
            if let pitchSignal, let baselinePitchSignal {
                landmarkChange = abs(pitchSignal - baselinePitchSignal)
            } else {
                landmarkChange = 0
            }
            return (landmarkChange >= 0.012 || abs(pitch) >= 0.035)
                && abs(yaw) < 0.18 && abs(roll) < 0.15
        case .closer:
            return baselineWidth.map { faceWidth > $0 * 1.18 } ?? false
        case .farther:
            return baselineWidth.map { faceWidth < $0 * 0.82 } ?? false
        }
    }
}

enum PoseBucket: String, CaseIterable, Sendable {
    case left, center, right

    static func from(yaw: Double) -> Self {
        if yaw < -0.12 { return .left }
        if yaw > 0.12 { return .right }
        return .center
    }
}
