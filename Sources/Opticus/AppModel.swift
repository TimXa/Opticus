import AppKit
import Foundation
import SwiftUI
import Vision

enum SettingsSection: String, Identifiable {
    case camera, calibration, scale

    var id: String { rawValue }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var frame: FrameAnalysis?
    @Published var previewImage: CGImage?
    @Published var glassesState: GlassesState = .unknown
    @Published var probability = 0.5
    @Published var rawProbability = 0.5
    @Published var neuralProbability: Double?
    @Published var rawPrediction: RawPrediction?
    @Published var decisionCandidate: GlassesState = .unknown
    @Published var decisionProgress = 0.0
    @Published var decisionMessage = "Запуск…"
    @Published var measurementReliable = false
    @Published var ownerVerified = true
    @Published var isRunning = false
    @Published var recognitionEnabled = true
    @Published var diagnosticsVisible = false
    @Published var bubbleHovered = false
    @Published var bubbleSize: CGFloat = 220
    @Published var bubbleVisible = true
    @Published var cameraEmbeddedInSettings = false
    @Published var automaticScaling = false
    @Published var errorMessage: String?
    @Published var calibrationLabel: CalibrationLabel?
    @Published var calibrationStage: CalibrationStage?
    @Published var calibrationCounts: [CalibrationPose: Int] = [:]
    @Published var scaleTransitionState: GlassesState?
    @Published var settingsSection: SettingsSection = .camera
    @Published var withGlassesModeID = ""
    @Published var withoutGlassesModeID = ""

    let camera = CameraService()
    let displayScaler = DisplayScaler()
    private let analyzer = FrameAnalyzer()
    private let previewRenderer = PreviewRenderer()
    private var profile = CalibrationProfile(withGlasses: [], withoutGlasses: [])
    private var filter = TemporalDecisionFilter()
    private var lastAppliedState: GlassesState = .unknown
    private var analysisInFlight = false
    private var previewInFlight = false
    private var lastAnalysisStart = 0.0
    private var hoverDismissTask: Task<Void, Never>?
    private var scaleTransitionTask: Task<Void, Never>?
    private var calibrationBaselineWidth: Double?
    private var calibrationBaselinePitchSignal: Double?
    private var calibrationSamples: [VisionVector] = []
    private var calibrationFacePrint: VNFeaturePrintObservation?
    private var ownerFacePrints: [VNFeaturePrintObservation] = []
    private var lastCalibrationCapture = 0.0
    private let defaults = UserDefaults.standard

    var isCalibrated: Bool { profile.isReady }
    var hasWithGlassesCalibration: Bool {
        profile.withGlasses.count >= CalibrationPose.samplesPerClass
    }
    var hasWithoutGlassesCalibration: Bool {
        profile.withoutGlasses.count >= CalibrationPose.samplesPerClass
    }
    var calibrationProgress: Double {
        let required = Double(CalibrationPose.samplesPerClass)
        return min(Double(calibrationCounts.values.reduce(0, +)) / required, 1)
    }

    var currentCalibrationPose: CalibrationPose? {
        CalibrationPose.allCases.first {
            calibrationCounts[$0, default: 0] < CalibrationPose.samplesPerPose
        }
    }

    var completedCalibrationPoses: Set<CalibrationPose> {
        Set(CalibrationPose.allCases.filter {
            calibrationCounts[$0, default: 0] >= CalibrationPose.samplesPerPose
        })
    }

    var currentPoseSamples: Int {
        currentCalibrationPose.map { calibrationCounts[$0, default: 0] }
            ?? CalibrationPose.samplesPerPose
    }

    init() {
        loadSettings()
        camera.onFrame = { [weak self] buffer in
            Task { @MainActor [weak self] in self?.accept(buffer) }
        }
        Task { [weak self] in
            await Task.yield()
            guard let self else { return }
            self.start()
            self.applyBubbleVisibility()
        }
    }

    func start() {
        guard !isRunning else { return }
        Task {
            do {
                try await camera.start()
                isRunning = true
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func stop() {
        camera.stop()
        isRunning = false
        glassesState = .unknown
        measurementReliable = false
        decisionMessage = "Камера выключена"
    }

    func requestCalibration(_ label: CalibrationLabel) {
        cancelScaleTransition()
        calibrationStage = .preparation(label)
        CalibrationWindow.shared.show(model: self)
    }

    func confirmCalibrationPreparation() {
        guard case let .preparation(label) = calibrationStage else { return }
        beginCalibration(label)
        calibrationStage = .scanning(label)
    }

    private func beginCalibration(_ label: CalibrationLabel) {
        calibrationLabel = label
        calibrationCounts = Dictionary(uniqueKeysWithValues: CalibrationPose.allCases.map { ($0, 0) })
        calibrationBaselineWidth = nil
        calibrationBaselinePitchSignal = nil
        calibrationSamples = []
        calibrationFacePrint = nil
        lastCalibrationCapture = 0
        filter.reset()
        decisionMessage = "Следуйте подсказке на экране"
    }

    func cancelCalibration() {
        calibrationLabel = nil
        calibrationStage = nil
        calibrationCounts = [:]
        calibrationSamples = []
        calibrationFacePrint = nil
        CalibrationWindow.shared.dismiss(model: self)
    }

    func setBubbleHover(_ hovered: Bool) {
        hoverDismissTask?.cancel()
        if hovered {
            bubbleHovered = true
        } else {
            hoverDismissTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(280))
                guard !Task.isCancelled else { return }
                self?.bubbleHovered = false
            }
        }
    }

    func selectSuggestedModes() {
        guard !displayScaler.modes.isEmpty else { return }
        let currentIndex = displayScaler.modes.firstIndex { $0.id == displayScaler.currentModeID }
            ?? displayScaler.modes.indices.last!
        withGlassesModeID = displayScaler.modes[currentIndex].id
        withoutGlassesModeID = displayScaler.modes[max(0, currentIndex - 2)].id
        saveSettings()
    }

    func saveSettings() {
        defaults.set(withGlassesModeID, forKey: "withGlassesModeID")
        defaults.set(withoutGlassesModeID, forKey: "withoutGlassesModeID")
        defaults.set(automaticScaling, forKey: "automaticScaling")
        defaults.set(Double(bubbleSize), forKey: "bubbleSize")
        defaults.set(bubbleVisible, forKey: "bubbleVisible")
        defaults.set(recognitionEnabled, forKey: "recognitionEnabled")
    }

    func setBubbleVisible(_ visible: Bool) {
        bubbleVisible = visible
        if !visible { previewImage = nil }
        saveSettings()
        applyBubbleVisibility()
    }

    func applyBubbleVisibility() {
        if bubbleVisible && !cameraEmbeddedInSettings && calibrationStage == nil {
            BubblePanel.shared.show(model: self)
        } else {
            BubblePanel.shared.hide()
        }
    }

    func setCameraEmbedded(_ embedded: Bool) {
        guard cameraEmbeddedInSettings != embedded else { return }
        cameraEmbeddedInSettings = embedded
        applyBubbleVisibility()
    }

    func setRecognitionEnabled(_ enabled: Bool) {
        recognitionEnabled = enabled
        if !enabled {
            filter.reset()
            glassesState = .unknown
            measurementReliable = false
            decisionProgress = 0
            decisionMessage = "Распознавание выключено"
            cancelScaleTransition()
        }
        saveSettings()
    }

    func setBubbleSize(_ value: CGFloat, anchor: BubbleResizeAnchor = .topRight) {
        bubbleSize = min(max(value, 220), 420)
        BubblePanel.shared.resize(for: bubbleSize, anchor: anchor)
    }

    func apply(modeID: String) {
        guard !modeID.isEmpty else { return }
        do {
            try displayScaler.apply(modeID: modeID)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            automaticScaling = false
        }
    }

    func cancelScaleTransition() {
        scaleTransitionTask?.cancel()
        scaleTransitionTask = nil
        scaleTransitionState = nil
        lastAppliedState = glassesState
        ScaleTransitionWindow.shared.dismiss()
    }

    func openScaleSettings() {
        cancelScaleTransition()
        settingsSection = .scale
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    private func accept(_ buffer: SendablePixelBuffer) {
        let needsPreview = bubbleVisible || cameraEmbeddedInSettings || calibrationStage != nil
        if needsPreview, !previewInFlight {
            previewInFlight = true
            Task.detached(priority: .high) { [previewRenderer, buffer] in
                let image = previewRenderer.render(pixelBuffer: buffer.value)
                await MainActor.run { [weak self] in
                    self?.previewInFlight = false
                    if let image { self?.previewImage = image }
                }
            }
        }

        let needsAnalysis = recognitionEnabled || calibrationStage != nil || diagnosticsVisible
        guard needsAnalysis else { return }
        let now = CACurrentMediaTime()
        guard now - lastAnalysisStart >= 1.0 / 8.0 else { return }
        guard !analysisInFlight else { return }
        lastAnalysisStart = now
        analysisInFlight = true
        let ownerReferences = OwnerFacePrints(values: ownerFacePrints)
        let needsLandmarks = calibrationStage != nil || (bubbleVisible && diagnosticsVisible)
        let captureOwnerFacePrint = calibrationLabel != nil
        Task.detached(priority: .userInitiated) {
            [analyzer, buffer, ownerReferences, needsLandmarks, captureOwnerFacePrint] in
            let result = try? analyzer.analyze(
                pixelBuffer: buffer.value,
                ownerFacePrints: ownerReferences,
                needsLandmarks: needsLandmarks,
                captureOwnerFacePrint: captureOwnerFacePrint
            )
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.analysisInFlight = false
                guard let result else { return }
                self.consume(result)
            }
        }
    }

    private func consume(_ result: FrameAnalysis) {
        if bubbleVisible || cameraEmbeddedInSettings || calibrationStage != nil {
            frame = result
        }
        guard let vector = result.vector else {
            filter.reset()
            glassesState = .unknown
            measurementReliable = false
            decisionCandidate = .unknown
            decisionProgress = 0
            rawPrediction = nil
            decisionMessage = result.foreignFaceDetected
                ? "Владелец не найден"
                : "Лицо не найдено"
            return
        }

        if let label = calibrationLabel {
            captureCalibration(
                vector, yaw: result.yaw, roll: result.roll,
                pitch: result.pitch,
                pitchSignal: result.pitchSignal,
                faceWidth: result.faceWidth, facePrint: result.facePrint, label: label
            )
            return
        }
        guard recognitionEnabled else { return }
        let prediction = profile.prediction(for: vector)
        rawPrediction = prediction
        neuralProbability = result.neuralGlassesProbability
        guard let combinedProbability = RecognitionSignal.fused(
            neural: result.neuralGlassesProbability,
            personal: prediction?.glassesProbability
        ) else {
            glassesState = .unknown
            measurementReliable = false
            decisionMessage = "Модель распознавания недоступна"
            return
        }
        rawProbability = combinedProbability

        guard verifyOwner(result.facePrint) else {
            filter.reset()
            glassesState = .unknown
            measurementReliable = false
            decisionCandidate = .unknown
            decisionProgress = 0
            probability = 0.5
            decisionMessage = "Другое лицо"
            return
        }

        guard abs(result.yaw) < 0.28, abs(result.roll) < 0.28 else {
            filter.reset()
            glassesState = .unknown
            measurementReliable = false
            decisionCandidate = .unknown
            decisionProgress = 0
            decisionMessage = "Повернитесь к камере"
            return
        }

        guard abs(result.pitch) < 0.34 else {
            filter.reset()
            glassesState = .unknown
            measurementReliable = false
            decisionCandidate = .unknown
            decisionProgress = 0
            decisionMessage = "Поднимите подбородок"
            return
        }

        measurementReliable = true
        let state = filter.update(
            probability: combinedProbability,
            now: CACurrentMediaTime()
        )
        probability = filter.smoothedProbability
        decisionCandidate = filter.candidateState
        decisionProgress = filter.candidateProgress
        glassesState = state
        updateDecisionMessage()
        applyScaleIfNeeded(for: state)
    }

    private func captureCalibration(
        _ vector: VisionVector,
        yaw: Double,
        roll: Double,
        pitch: Double,
        pitchSignal: Double?,
        faceWidth: Double,
        facePrint: VNFeaturePrintObservation?,
        label: CalibrationLabel
    ) {
        guard let pose = currentCalibrationPose,
              pose.matches(
                yaw: yaw, roll: roll, pitch: pitch,
                pitchSignal: pitchSignal,
                baselinePitchSignal: calibrationBaselinePitchSignal,
                faceWidth: faceWidth,
                baselineWidth: calibrationBaselineWidth
              ) else { return }
        let now = CACurrentMediaTime()
        guard now - lastCalibrationCapture >= 0.22 else { return }
        lastCalibrationCapture = now
        if pose == .front, calibrationBaselineWidth == nil {
            calibrationBaselineWidth = faceWidth
        }
        if pose == .front, let pitchSignal {
            let count = Double(calibrationCounts[.front, default: 0])
            if let baseline = calibrationBaselinePitchSignal {
                calibrationBaselinePitchSignal = (baseline * count + pitchSignal) / (count + 1)
            } else {
                calibrationBaselinePitchSignal = pitchSignal
            }
        }
        if pose == .front, calibrationFacePrint == nil {
            calibrationFacePrint = facePrint
        }
        calibrationCounts[pose, default: 0] += 1
        calibrationSamples.append(vector)

        if calibrationCounts.values.reduce(0, +) >= CalibrationPose.samplesPerClass {
            if label == .withGlasses { profile.withGlasses = calibrationSamples }
            else { profile.withoutGlasses = calibrationSamples }
            if let calibrationFacePrint {
                replaceOwnerFacePrint(calibrationFacePrint, for: label)
            }
            calibrationSamples = []
            calibrationFacePrint = nil
            calibrationLabel = nil
            calibrationStage = .success(label)
            decisionMessage = profile.isReady
                ? "Калибровка готова"
                : "Запишите второе состояние"
            if let data = try? JSONEncoder().encode(profile) {
                defaults.set(data, forKey: "calibrationProfile")
            }
            objectWillChange.send()
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(1650))
                guard let self else { return }
                self.calibrationStage = nil
                CalibrationWindow.shared.dismiss(model: self)
            }
        }
    }

    private func updateDecisionMessage() {
        if decisionCandidate != .unknown, decisionCandidate != glassesState, decisionProgress > 0 {
            let remaining = TemporalDecisionFilter.defaultDwell * (1 - decisionProgress)
            let target = decisionCandidate == .withGlasses ? "Очки" : "Без очков"
            decisionMessage = "\(target): \(remaining.formatted(.number.precision(.fractionLength(1)))) с"
        } else if probability >= TemporalDecisionFilter.glassesThreshold {
            decisionMessage = "Очки надеты"
        } else if probability <= TemporalDecisionFilter.bareThreshold {
            decisionMessage = "Без очков"
        } else {
            decisionMessage = "Не уверен"
        }
    }

    private func verifyOwner(_ facePrint: VNFeaturePrintObservation?) -> Bool {
        guard !ownerFacePrints.isEmpty else {
            ownerVerified = true
            return true
        }
        guard let facePrint else {
            ownerVerified = false
            return false
        }
        let distances = ownerFacePrints.compactMap { reference -> Float? in
            var distance: Float = 0
            guard (try? facePrint.computeDistance(&distance, to: reference)) != nil else { return nil }
            return distance
        }
        guard let closest = distances.min() else {
            ownerVerified = false
            return false
        }
        ownerVerified = closest < RecognitionSignal.ownerMatchThreshold
        return ownerVerified
    }

    private func replaceOwnerFacePrint(
        _ facePrint: VNFeaturePrintObservation,
        for label: CalibrationLabel
    ) {
        let key = label == .withGlasses ? "ownerFacePrintWithGlasses" : "ownerFacePrintWithoutGlasses"
        if let data = try? NSKeyedArchiver.archivedData(
            withRootObject: facePrint,
            requiringSecureCoding: true
        ) {
            defaults.set(data, forKey: key)
        }
        loadOwnerFacePrints()
    }

    private func loadOwnerFacePrints() {
        ownerFacePrints = ["ownerFacePrintWithGlasses", "ownerFacePrintWithoutGlasses"]
            .compactMap { key in
                guard let data = defaults.data(forKey: key) else { return nil }
                return try? NSKeyedUnarchiver.unarchivedObject(
                    ofClass: VNFeaturePrintObservation.self,
                    from: data
                )
            }
    }

    private func applyScaleIfNeeded(for state: GlassesState) {
        guard automaticScaling,
              calibrationStage == nil,
              state != .unknown,
              state != lastAppliedState else { return }
        let mode = state == .withGlasses ? withGlassesModeID : withoutGlassesModeID
        guard !mode.isEmpty else { return }
        guard displayScaler.currentModeID != mode else {
            lastAppliedState = state
            return
        }
        lastAppliedState = state
        scaleTransitionTask?.cancel()
        scaleTransitionState = state
        ScaleTransitionWindow.shared.show(model: self)
        scaleTransitionTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard let self, !Task.isCancelled, self.scaleTransitionState == state else { return }
            self.applyModeWithDisplayFade(modeID: mode)
            ScaleTransitionWindow.shared.fillCurrentScreen()
            try? await Task.sleep(for: .milliseconds(950))
            guard !Task.isCancelled, self.scaleTransitionState == state else { return }
            self.scaleTransitionState = nil
            self.scaleTransitionTask = nil
            ScaleTransitionWindow.shared.dismiss()
        }
    }

    private func applyModeWithDisplayFade(modeID: String) {
        var token = CGDisplayFadeReservationToken(0)
        let acquired = CGAcquireDisplayFadeReservation(2, &token) == .success
        if acquired {
            CGDisplayFade(token, 0.20, 0, 1, 0, 0, 0, 1)
        }
        apply(modeID: modeID)
        ScaleTransitionWindow.shared.fillCurrentScreen()
        if acquired {
            CGDisplayFade(token, 0.26, 1, 0, 0, 0, 0, 1)
            CGReleaseDisplayFadeReservation(token)
        }
    }

    private func loadSettings() {
        loadOwnerFacePrints()
        if let data = defaults.data(forKey: "calibrationProfile"),
           let decoded = try? JSONDecoder().decode(CalibrationProfile.self, from: data) {
            profile = decoded
        }
        withGlassesModeID = defaults.string(forKey: "withGlassesModeID") ?? ""
        withoutGlassesModeID = defaults.string(forKey: "withoutGlassesModeID") ?? ""
        automaticScaling = defaults.bool(forKey: "automaticScaling")
        bubbleVisible = defaults.object(forKey: "bubbleVisible") == nil
            ? true
            : defaults.bool(forKey: "bubbleVisible")
        recognitionEnabled = defaults.object(forKey: "recognitionEnabled") == nil
            ? true
            : defaults.bool(forKey: "recognitionEnabled")
        let savedBubbleSize = defaults.double(forKey: "bubbleSize")
        if savedBubbleSize > 0 { bubbleSize = min(max(savedBubbleSize, 220), 420) }
        if !profile.isReady { automaticScaling = false }
        if withGlassesModeID.isEmpty || withoutGlassesModeID.isEmpty {
            selectSuggestedModes()
        }
    }
}
