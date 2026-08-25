import AppKit
import SceneKit
import SwiftUI

enum SteelPalette {
    static let background = Color(red: 20 / 255, green: 18 / 255, blue: 11 / 255)
    static let backgroundRaised = Color(red: 29 / 255, green: 27 / 255, blue: 21 / 255)
    static let panel = Color(red: 32 / 255, green: 30 / 255, blue: 24 / 255)
    static let ink = Color(red: 237 / 255, green: 236 / 255, blue: 236 / 255)
    static let body = ink.opacity(0.78)
    static let faint = ink.opacity(0.64)
    static let line = ink.opacity(0.10)
    static let lineStrong = ink.opacity(0.15)
    static let accentBlue = Color(red: 99 / 255, green: 139 / 255, blue: 163 / 255)
    static let success = Color(red: 99 / 255, green: 135 / 255, blue: 106 / 255)
}

struct SteelIcon: View {
    let name: String
    var size: CGFloat = 18

    var body: some View {
        Group {
            if let url = resourceURL,
               let image = NSImage(contentsOf: url) {
                Image(nsImage: template(image))
                    .resizable().scaledToFit()
            } else {
                Image(systemName: name)
                    .resizable().scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var resourceURL: URL? {
        let fileExtension = name == "steelrework-logo" ? "png" : "svg"
        return Bundle.main.url(forResource: name, withExtension: fileExtension)
            ?? Bundle.module.url(forResource: name, withExtension: fileExtension)
    }

    private func template(_ image: NSImage) -> NSImage {
        image.isTemplate = true
        return image
    }
}

private struct PointingHandCursor: ViewModifier {
    func body(content: Content) -> some View {
        content.onContinuousHover { phase in
            switch phase {
            case .active: NSCursor.pointingHand.set()
            case .ended: NSCursor.arrow.set()
            }
        }
    }
}

private extension View {
    func pointingHandCursor() -> some View {
        modifier(PointingHandCursor())
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 210)
            Rectangle().fill(SteelPalette.line).frame(width: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    contentHeader
                    if let error = model.errorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(error).foregroundStyle(SteelPalette.ink)
                        }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel("Ошибка: \(error)")
                    }
                    sectionContent
                }
                .padding(30)
            }
        }
        .frame(minWidth: 690, idealWidth: 750, minHeight: 440, idealHeight: 500)
        .background(SteelPalette.background)
        .foregroundStyle(SteelPalette.body)
        .tint(SteelPalette.ink)
        .environment(\.controlSize, .large)
        .preferredColorScheme(.dark)
        .onAppear {
            model.setCameraEmbedded(model.settingsSection == .camera)
            if !model.isRunning { model.start() }
        }
        .onDisappear { model.setCameraEmbedded(false) }
        .onChange(of: model.settingsSection) { _, section in
            model.setCameraEmbedded(section == .camera)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                NSWorkspace.shared.open(URL(string: "https://t.me/steelrework")!)
            } label: {
                HStack(spacing: 11) {
                    SteelIcon(name: "steelrework-logo", size: 27)
                        .foregroundStyle(SteelPalette.ink)
                    Text("SteelRework")
                        .font(.custom("Days One", size: 16))
                        .foregroundStyle(SteelPalette.ink)
                }
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help("Открыть SteelRework в Telegram")
            .padding(.horizontal, 16)
            .padding(.bottom, 22)

            ForEach([SettingsSection.camera, .calibration, .scale]) { section in
                SidebarItem(
                    title: section.title,
                    icon: section.icon,
                    selected: model.settingsSection == section
                ) {
                    model.settingsSection = section
                }
            }
            Spacer()
        }
        .padding(.vertical, 24)
        .background(Color.black.opacity(0.14))
    }

    private var contentHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.settingsSection.title)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .foregroundStyle(SteelPalette.ink)
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch model.settingsSection {
        case .camera:
            cameraCard
        case .calibration:
            calibrationCard
        case .scale:
            scaleCard
        }
    }

    private var cameraCard: some View {
        PlainCard {
            VStack(spacing: 18) {
                HStack(alignment: .top, spacing: 34) {
                    VStack(alignment: .leading, spacing: 12) {
                        settingsToggle(
                            "Камера",
                            isOn: Binding(
                                get: { model.isRunning },
                                set: { $0 ? model.start() : model.stop() }
                            )
                        )
                        settingsToggle(
                            "Распознавание",
                            isOn: Binding(
                                get: { model.recognitionEnabled },
                                set: { model.setRecognitionEnabled($0) }
                            )
                        )
                        .disabled(!model.isRunning)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 12) {
                        settingsToggle(
                            "Кружок",
                            isOn: Binding(
                                get: { model.bubbleVisible },
                                set: { model.setBubbleVisible($0) }
                            )
                        )
                        settingsToggle("Расчёты", isOn: $model.diagnosticsVisible)
                            .disabled(!model.isRunning)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                CameraBubbleView(model: model, embedded: true)
                    .frame(width: 184, height: 184)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func settingsToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        SettingsToggleRow(title: title, isOn: isOn)
    }

    private var calibrationCard: some View {
        PlainCard {
            HStack(spacing: 10) {
                calibrationButton(.withoutGlasses)
                calibrationButton(.withGlasses)
            }
        }
    }

    private func calibrationButton(_ label: CalibrationLabel) -> some View {
        let complete = label == .withGlasses
            ? model.hasWithGlassesCalibration
            : model.hasWithoutGlassesCalibration
        return Button {
            model.requestCalibration(label)
        } label: {
            HStack(spacing: 8) {
                if label == .withGlasses {
                    SteelIcon(name: "app-eyeglasses", size: 23)
                } else {
                    Image(systemName: "eye")
                        .font(.system(size: 20, weight: .medium))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(label == .withGlasses ? "В очках" : "Без очков")
                        .font(.title3.weight(.semibold))
                }
                Spacer()
                if complete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(SteelPalette.ink)
                }
            }
                .frame(maxWidth: .infinity)
                .frame(height: 58)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!model.isRunning || model.calibrationLabel != nil)
        .pointingHandCursor()
    }

    private var scaleCard: some View {
        PlainCard {
            VStack(alignment: .leading, spacing: 14) {
                modeRow(
                    title: "В очках", icon: "eyeglasses",
                    selection: $model.withGlassesModeID
                )
                Divider()
                modeRow(
                    title: "Без очков", icon: "eye",
                    selection: $model.withoutGlassesModeID
                )
                Divider()
                Toggle(isOn: Binding(
                    get: { model.automaticScaling },
                    set: { value in model.automaticScaling = value; model.saveSettings() }
                )) {
                    Text("Автоматически")
                }
                .disabled(!model.isCalibrated)
            }
        }
    }

    private func modeRow(title: String, icon: String, selection: Binding<String>) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 7) {
                if icon == "eyeglasses" {
                    SteelIcon(name: "app-eyeglasses", size: 19)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 19)
                }
                Text(title)
            }
            .frame(width: 145, alignment: .leading)
            Picker(title, selection: selection) {
                ForEach(model.displayScaler.modes) { mode in
                    Text(mode.title).tag(mode.id)
                }
            }
            .labelsHidden()
            .onChange(of: selection.wrappedValue) { _, _ in model.saveSettings() }
            Button("Проверить") { model.apply(modeID: selection.wrappedValue) }
                .buttonStyle(.bordered)
                .pointingHandCursor()
        }
    }

}

private struct PlainCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SteelPalette.backgroundRaised, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(SteelPalette.line)
            }
    }
}

private extension SettingsSection {
    var title: String {
        switch self {
        case .camera: "Камера"
        case .calibration: "Калибровка"
        case .scale: "Масштаб"
        }
    }

    var icon: String {
        switch self {
        case .camera: "camera"
        case .calibration: "eye"
        case .scale: "monitor"
        }
    }
}

private struct SidebarItem: View {
    let title: String
    let icon: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                SteelIcon(name: icon, size: 16)
                Text(title)
                Spacer()
                if selected {
                    Circle().fill(SteelPalette.ink).frame(width: 5, height: 5)
                }
            }
            .font(.system(size: 15, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? SteelPalette.ink : SteelPalette.body)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(selected ? SteelPalette.panel : .clear, in: RoundedRectangle(cornerRadius: 11))
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: 11).stroke(SteelPalette.line)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .padding(.horizontal, 10)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 12) {
                Text(title)
                    .font(.body.weight(.medium))
                Spacer(minLength: 10)
                Toggle("", isOn: .constant(isOn))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .accessibilityValue(isOn ? "Включено" : "Выключено")
    }
}

struct CalibrationExperienceView: View {
    @ObservedObject var model: AppModel
    @State private var stageFlash = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            Color.black.opacity(isSuccessful ? 0 : 0.50)
                .ignoresSafeArea()
            if case let .preparation(label) = model.calibrationStage {
                preparation(label)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else if model.calibrationStage != nil {
                scanning
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
            SteelPalette.success
                .opacity(stageFlash ? 0.72 : 0)
                .blendMode(.plusLighter)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .preferredColorScheme(.dark)
        .animation(.easeOut(duration: 0.22), value: model.calibrationStage)
        .onChange(of: model.completedCalibrationPoses.count) { previous, completed in
            guard completed > previous else { return }
            stageFlash = true
            playStageChime()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(80))
                withAnimation(.easeOut(duration: 0.58)) {
                    stageFlash = false
                }
            }
        }
        .onExitCommand { model.cancelCalibration() }
    }

    private var isSuccessful: Bool {
        if case .success = model.calibrationStage { return true }
        return false
    }

    private func preparation(_ label: CalibrationLabel) -> some View {
        GeometryReader { geometry in
            let circleSide = min(540, geometry.size.height * 0.62, geometry.size.width * 0.42)
            HStack(spacing: max(54, geometry.size.width * 0.06)) {
                ZStack {
                    Circle().fill(.black)
                    if let image = model.previewImage {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFill()
                    }
                    if let frame = model.frame {
                        FaceContourOverlay(frame: frame)
                    }
                }
                .frame(width: circleSide, height: circleSide)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(SteelPalette.lineStrong, lineWidth: 2))
                .shadow(color: .black.opacity(0.22), radius: 8, y: 3)

                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(label.preparationTitle)
                            .font(.system(size: 58, weight: .semibold, design: .rounded))
                            .foregroundStyle(SteelPalette.ink)
                        Text(label.preparationDetail)
                            .font(.title2)
                            .foregroundStyle(SteelPalette.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 12) {
                        Button { model.cancelCalibration() } label: {
                            Text("Отмена")
                                .font(.title3.weight(.semibold))
                                .frame(width: 170, height: 62)
                                .background(SteelPalette.panel, in: RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(SteelPalette.lineStrong))
                        }
                            .buttonStyle(.plain)
                            .pointingHandCursor()
                            .keyboardShortcut(.cancelAction)
                        Button { model.confirmCalibrationPreparation() } label: {
                            Text("Я готов")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(SteelPalette.background)
                                .frame(width: 190, height: 62)
                                .background(SteelPalette.ink, in: RoundedRectangle(cornerRadius: 14))
                        }
                            .buttonStyle(.plain)
                            .pointingHandCursor()
                            .keyboardShortcut(.defaultAction)
                    }
                }
                .frame(maxWidth: 520, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(56)
        }
    }

    private var scanning: some View {
        GeometryReader { geometry in
            let available = geometry.size
            let scanSide = min(560, available.width * 0.43, available.height * 0.62)
            let guideWidth = min(500, scanSide * 0.90)
            let guideHeight = min(520, scanSide * 0.94)
            let gap = min(64, max(30, available.width * 0.04))
            let groupWidth = scanSide + gap + guideWidth
            let groupStart = max(24, (available.width - groupWidth) / 2)
            let circleSide = isSuccessful ? model.bubbleSize : scanSide
            let center = isSuccessful ? returnPoint(in: geometry) : CGPoint(
                x: groupStart + scanSide / 2,
                y: available.height / 2 - 12
            )

            ZStack {
                cameraCircle
                    .frame(width: circleSide, height: circleSide)
                    .position(center)
                    .shadow(color: .black.opacity(isSuccessful ? 0 : 0.22), radius: 8, y: 3)
                    .animation(.smooth(duration: 1.15), value: isSuccessful)

                if !isSuccessful {
                    Text("\(Int((model.calibrationProgress * 100).rounded()))%")
                        .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(SteelPalette.ink)
                        .contentTransition(.numericText())
                        .position(x: center.x, y: center.y - scanSide / 2 - 46)
                        .transition(.opacity)

                    Text(model.currentCalibrationPose?.title ?? "Готово")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(SteelPalette.ink)
                    .position(x: center.x, y: center.y + scanSide / 2 + 54)
                    .transition(.opacity)

                    if let pose = model.currentCalibrationPose {
                        PoseGuideIllustration(pose: pose)
                            .frame(width: guideWidth, height: guideHeight)
                            .position(x: groupStart + scanSide + gap + guideWidth / 2, y: center.y)
                            .transition(.opacity)
                    }

                    Button("Отмена") { model.cancelCalibration() }
                        .buttonStyle(.plain)
                        .foregroundStyle(SteelPalette.faint)
                        .position(x: available.width - 54, y: 34)
                        .pointingHandCursor()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.50), value: isSuccessful)
        }
    }

    private var cameraCircle: some View {
        ZStack {
            Circle().fill(.black)
            if let image = model.previewImage {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
            }
            if let frame = model.frame {
                FaceContourOverlay(frame: frame)
            }
            if isSuccessful {
                Circle().fill(SteelPalette.success.opacity(0.28))
                Image(systemName: "checkmark")
                    .font(.system(size: max(28, model.bubbleSize * 0.20), weight: .bold))
                    .foregroundStyle(.white)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .clipShape(Circle())
        .overlay {
            if !isSuccessful {
                CalibrationProgressRing(
                    progress: model.calibrationProgress,
                    completed: model.completedCalibrationPoses.count
                )
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.30), value: isSuccessful)
    }

    private func returnPoint(in geometry: GeometryProxy) -> CGPoint {
        guard let screen = NSScreen.main,
              let global = BubblePanel.shared.circleCenterOnScreen else {
            return CGPoint(x: geometry.size.width - model.bubbleSize / 2 - 24, y: model.bubbleSize / 2 + 24)
        }
        return CGPoint(
            x: global.x - screen.frame.minX,
            y: screen.frame.maxY - global.y
        )
    }

    private func playStageChime() {
        guard let url = Bundle.module.url(forResource: "calibration-success", withExtension: "wav") else { return }
        let sound = NSSound(contentsOf: url, byReference: false)
        sound?.volume = 0.42
        sound?.play()
    }
}

private struct CalibrationProgressRing: View {
    let progress: Double
    let completed: Int

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let lineWidth = max(6, side * 0.018)
            ZStack {
                Circle().stroke(.white.opacity(0.18), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(SteelPalette.success, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Canvas { context, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    let radius = (min(size.width, size.height) - lineWidth) / 2
                    let dot = max(6, lineWidth * 0.72)
                    let poseCount = CalibrationPose.allCases.count
                    for index in 0..<poseCount {
                        let angle = Double(index) / Double(poseCount) * 2 * Double.pi - Double.pi / 2
                        let point = CGPoint(
                            x: center.x + cos(angle) * radius,
                            y: center.y + sin(angle) * radius
                        )
                        let rect = CGRect(x: point.x - dot / 2, y: point.y - dot / 2, width: dot, height: dot)
                        context.fill(
                            Path(ellipseIn: rect),
                            with: .color(index < completed ? SteelPalette.success : .black.opacity(0.48))
                        )
                        context.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.42)), lineWidth: 0.8)
                    }
                }
            }
            .padding(lineWidth / 2 + 1)
        }
        .animation(.smooth(duration: 0.25), value: progress)
        .accessibilityLabel("Прогресс калибровки")
        .accessibilityValue(progress.formatted(.percent.precision(.fractionLength(0))))
    }
}

private struct PoseGuideIllustration: View {
    let pose: CalibrationPose

    var body: some View {
        ZStack {
            PoseGuideModel(pose: pose)
                .frame(width: 520, height: 500)
                .offset(y: 4)
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .white, location: 0),
                            .init(color: .white, location: 0.78),
                            .init(color: .clear, location: 0.98),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            Rectangle()
                .fill(.ultraThinMaterial)
                .mask {
                    LinearGradient(
                        colors: [.clear, .clear, .white.opacity(0.68)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .blur(radius: 18)
                .allowsHitTesting(false)
            PoseDirectionArrow(pose: pose)
                .id(pose)
        }
        .frame(width: 520, height: 500)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Пример движения: \(pose.title)")
    }
}

private struct PoseDirectionArrow: View {
    let pose: CalibrationPose
    @State private var moving = false

    var body: some View {
        GeometryReader { geometry in
            if pose != .front {
                Image(systemName: symbol)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.black.opacity(0.56), in: Circle())
                    .position(position(in: geometry.size))
                    .offset(moving ? travel : .zero)
                    .animation(
                        .easeInOut(duration: 0.90).repeatForever(autoreverses: true),
                        value: moving
                    )
                    .onAppear { moving = true }
            }
        }
        .accessibilityHidden(true)
    }

    private var symbol: String {
        switch pose {
        case .turnLeft: "arrow.left"
        case .turnRight: "arrow.right"
        case .tiltLeft: "arrow.down.left"
        case .tiltRight: "arrow.down.right"
        case .lookDown: "arrow.down"
        case .closer: "arrow.down"
        case .farther: "arrow.up"
        case .front: "circle"
        }
    }

    private var travel: CGSize {
        switch pose {
        case .turnLeft: CGSize(width: -15, height: 0)
        case .turnRight: CGSize(width: 15, height: 0)
        case .tiltLeft: CGSize(width: -10, height: 10)
        case .tiltRight: CGSize(width: 10, height: 10)
        case .lookDown: CGSize(width: 0, height: 14)
        case .closer: CGSize(width: 0, height: 14)
        case .farther: CGSize(width: 0, height: -14)
        case .front: .zero
        }
    }

    private func position(in size: CGSize) -> CGPoint {
        switch pose {
        case .turnLeft: CGPoint(x: size.width * 0.20, y: size.height * 0.43)
        case .turnRight: CGPoint(x: size.width * 0.80, y: size.height * 0.43)
        case .tiltLeft: CGPoint(x: size.width * 0.23, y: size.height * 0.30)
        case .tiltRight: CGPoint(x: size.width * 0.77, y: size.height * 0.30)
        case .lookDown: CGPoint(x: size.width * 0.50, y: size.height * 0.22)
        case .closer, .farther: CGPoint(x: size.width * 0.50, y: size.height * 0.18)
        case .front: CGPoint(x: size.width / 2, y: size.height / 2)
        }
    }
}

private struct PoseGuideModel: NSViewRepresentable {
    let pose: CalibrationPose

    final class Coordinator {
        let guideNode = SCNNode()
        var headNodes: [SCNNode] = []
        var restingHeadAngles: [SCNVector3] = []
        var pose: CalibrationPose?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling4X
        view.scene = makeScene(coordinator: context.coordinator)
        view.isPlaying = true
        view.rendersContinuously = true
        return view
    }

    func updateNSView(_ view: SCNView, context: Context) {
        guard context.coordinator.pose != pose else { return }
        context.coordinator.pose = pose
        animate(context.coordinator)
    }

    private func makeScene(coordinator: Coordinator) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = NSColor.clear
        let guideNode = coordinator.guideNode
        scene.rootNode.addChildNode(guideNode)

        if let url = Bundle.module.url(forResource: "calibration_mannequin", withExtension: "usdc"),
           let source = try? SCNScene(url: url) {
            let model = SCNNode()
            let character = source.rootNode.clone()
            character.eulerAngles.x = -.pi / 2
            model.addChildNode(character)
            let bounds = model.boundingBox
            let height = max(bounds.max.y - bounds.min.y, 0.01)
            let center = SCNVector3(
                (bounds.min.x + bounds.max.x) / 2,
                bounds.min.y + height * 0.88,
                (bounds.min.z + bounds.max.z) / 2
            )
            model.pivot = SCNMatrix4MakeTranslation(center.x, center.y, center.z)
            let scale = 10.0 / height
            model.scale = SCNVector3(scale, scale, scale)
            model.enumerateChildNodes { node, _ in
                node.geometry?.materials.forEach {
                    $0.diffuse.contents = NSColor(white: 0.92, alpha: 1)
                    $0.emission.contents = NSColor(white: 0.035, alpha: 1)
                    $0.roughness.contents = 0.86
                    $0.metalness.contents = 0.04
                    $0.isDoubleSided = true
                }
            }
            model.childNode(withName: "mixamorig1_LeftArm", recursively: true)?.eulerAngles.x += 1.25
            model.childNode(withName: "mixamorig1_RightArm", recursively: true)?.eulerAngles.x += 1.25
            guideNode.addChildNode(model)
            if let head = model.childNode(withName: "mixamorig1_Head", recursively: true) {
                coordinator.headNodes.append(head)
                coordinator.restingHeadAngles.append(head.eulerAngles)
            }
        }

        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 42
        camera.position = SCNVector3(0, 0, 4.4)
        scene.rootNode.addChildNode(camera)

        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .omni
        key.light?.intensity = 520
        key.position = SCNVector3(-2.2, 2.4, 3.2)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .ambient
        fill.light?.intensity = 210
        fill.light?.color = NSColor(white: 0.92, alpha: 1)
        scene.rootNode.addChildNode(fill)
        return scene
    }

    private func animate(_ coordinator: Coordinator) {
        let node = coordinator.guideNode
        node.removeAllActions()
        node.eulerAngles = SCNVector3Zero
        node.position = SCNVector3Zero
        node.scale = SCNVector3(1, 1, 1)
        for (head, resting) in zip(coordinator.headNodes, coordinator.restingHeadAngles) {
            head.removeAllActions()
            head.eulerAngles = resting
        }

        if pose == .closer || pose == .farther {
            let closer = pose == .closer
            let bodyAngle: CGFloat = closer ? 0.17 : -0.19
            let target = SCNAction.group([
                .rotateTo(x: bodyAngle, y: 0, z: 0, duration: 0.95, usesShortestUnitArc: true),
                .scale(to: closer ? 1.09 : 0.91, duration: 0.95),
                .moveBy(x: 0, y: closer ? 0.02 : -0.07, z: closer ? 0.12 : -0.12, duration: 0.95),
            ])
            let reset = SCNAction.group([
                .rotateTo(x: 0, y: 0, z: 0, duration: 0.85, usesShortestUnitArc: true),
                .scale(to: 1, duration: 0.85),
                .move(to: SCNVector3Zero, duration: 0.85),
            ])
            runLoop(on: node, target: target, reset: reset)
            for (head, resting) in zip(coordinator.headNodes, coordinator.restingHeadAngles) {
                let targetHead = SCNAction.rotateTo(
                    x: resting.x - bodyAngle,
                    y: resting.y,
                    z: resting.z,
                    duration: 0.95,
                    usesShortestUnitArc: true
                )
                let resetHead = SCNAction.rotateTo(
                    x: resting.x,
                    y: resting.y,
                    z: resting.z,
                    duration: 0.85,
                    usesShortestUnitArc: true
                )
                runLoop(on: head, target: targetHead, reset: resetHead)
            }
            return
        }

        for (head, resting) in zip(coordinator.headNodes, coordinator.restingHeadAngles) {
            let targetAngles: SCNVector3 = switch pose {
            case .tiltLeft: SCNVector3(resting.x, resting.y, resting.z + 0.30)
            case .tiltRight: SCNVector3(resting.x, resting.y, resting.z - 0.30)
            case .turnLeft: SCNVector3(resting.x, resting.y - 0.50, resting.z)
            case .turnRight: SCNVector3(resting.x, resting.y + 0.50, resting.z)
            case .lookDown: SCNVector3(resting.x + 0.34, resting.y, resting.z)
            case .front: SCNVector3(resting.x - 0.07, resting.y, resting.z)
            case .closer, .farther: resting
            }
            let target = SCNAction.rotateTo(
                x: CGFloat(targetAngles.x),
                y: CGFloat(targetAngles.y),
                z: CGFloat(targetAngles.z),
                duration: 0.95,
                usesShortestUnitArc: true
            )
            let reset = SCNAction.rotateTo(
                x: CGFloat(resting.x),
                y: CGFloat(resting.y),
                z: CGFloat(resting.z),
                duration: 0.85,
                usesShortestUnitArc: true
            )
            runLoop(on: head, target: target, reset: reset)
        }
    }

    private func runLoop(on node: SCNNode, target: SCNAction, reset: SCNAction) {
        target.timingMode = .easeInEaseOut
        reset.timingMode = .easeInEaseOut
        node.runAction(.repeatForever(.sequence([
            target,
            .wait(duration: 0.45),
            reset,
            .wait(duration: 0.35),
        ])))
    }
}

struct CameraBubbleView: View {
    @ObservedObject var model: AppModel
    var embedded = false
    @State private var resizeStart: CGFloat?

    private enum ResizeEdge: Equatable {
        case top, bottom, left, right
    }

    private var side: CGFloat { embedded ? 184 : model.bubbleSize }
    private var panelWidth: CGFloat { side + 230 }
    private var panelHeight: CGFloat { side + 90 }

    @ViewBuilder
    var body: some View {
        if embedded {
            cameraCircle
                .frame(width: side, height: side)
                .accessibilityLabel("Превью камеры. \(model.glassesState.title).")
        } else {
            floatingBubble
        }
    }

    private var cameraCircle: some View {
        cameraSurface
            .clipShape(Circle())
            .overlay {
                Circle().strokeBorder(SteelPalette.ink.opacity(0.42), lineWidth: 1)
            }
    }

    private var floatingBubble: some View {
        ZStack(alignment: .topTrailing) {
            cameraCircle
                .frame(width: side, height: side)
                .contentShape(Circle())
                .overlay {
                    NativeWindowDragSurface(
                        passthroughCenter: !model.isRunning,
                        onFinished: { BubblePanel.shared.finishMove() }
                    )
                    .clipShape(Circle())
                    .onHover { model.setBubbleHover($0) }
                }
            if model.bubbleHovered {
                radialControls
                    .transition(.opacity)
                resizeHandles
                    .transition(.opacity)
            }
        }
        .frame(width: panelWidth, height: panelHeight, alignment: .topTrailing)
        .animation(.snappy(duration: 0.28, extraBounce: 0), value: model.bubbleHovered)
        .accessibilityLabel("Камера. \(model.glassesState.title).")
        .accessibilityHint("Перетащите круг, чтобы переместить его. Потяните за любую грань, чтобы изменить размер.")
    }

    private var resizeHandles: some View {
        let circleLeft = panelWidth - side
        let centerX = panelWidth - side / 2
        let centerY = side / 2
        return ZStack {
            resizeHandle(.top)
                .position(x: centerX, y: 7)
            resizeHandle(.bottom)
                .position(x: centerX, y: side - 7)
            resizeHandle(.left)
                .position(x: circleLeft + 7, y: centerY)
            resizeHandle(.right)
                .position(x: panelWidth - 7, y: centerY)
        }
        .frame(width: panelWidth, height: panelHeight)
    }

    private func resizeHandle(_ edge: ResizeEdge) -> some View {
        let horizontal = edge == .top || edge == .bottom
        return Capsule()
            .fill(SteelPalette.ink.opacity(0.88))
            .frame(width: horizontal ? 42 : 4, height: horizontal ? 4 : 42)
            .frame(width: horizontal ? 58 : 22, height: horizontal ? 22 : 58)
            .contentShape(Rectangle())
            .gesture(resizeGesture(edge))
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    model.setBubbleHover(true)
                    (horizontal ? NSCursor.resizeUpDown : NSCursor.resizeLeftRight).set()
                case .ended:
                    NSCursor.arrow.set()
                    model.setBubbleHover(false)
                }
            }
            .help("Изменить размер")
            .accessibilityLabel("Изменить размер камеры")
    }

    private func resizeGesture(_ edge: ResizeEdge) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if resizeStart == nil { resizeStart = model.bubbleSize }
                guard let resizeStart else { return }
                let delta: CGFloat
                let anchor: BubbleResizeAnchor
                switch edge {
                case .left:
                    delta = -value.translation.width
                    anchor = .topRight
                case .right:
                    delta = value.translation.width
                    anchor = .topLeft
                case .top:
                    delta = -value.translation.height
                    anchor = .bottomRight
                case .bottom:
                    delta = value.translation.height
                    anchor = .topRight
                }
                model.setBubbleSize(resizeStart + delta, anchor: anchor)
            }
            .onEnded { _ in
                resizeStart = nil
                model.saveSettings()
            }
    }

    private var cameraSurface: some View {
        ZStack {
            Color.black
            if model.isRunning, let image = model.previewImage {
                if let frame = model.frame, frame.faceRect != nil {
                    FaceTrackedCameraImage(image: image, frame: frame)
                    if model.diagnosticsVisible { diagnostics(frame) }
                } else {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            if model.isRunning, model.frame?.vector != nil {
                LinearGradient(
                    colors: [.black.opacity(0.46), .clear, .black.opacity(0.68)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            if model.diagnosticsVisible, hasActiveDecision {
                Circle()
                    .trim(from: 0, to: decisionConfidence)
                    .stroke(SteelPalette.accentBlue, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(4)
                    .allowsHitTesting(false)
            }
            if model.calibrationLabel != nil { calibrationCameraOverlay }
            if !model.isRunning {
                stoppedBubbleState
            } else if !model.recognitionEnabled {
                recognitionOffBubbleState
            } else if model.frame?.vector == nil {
                missingFaceBubbleState
            } else {
                liveBubbleState
            }
        }
    }

    private var stoppedBubbleState: some View {
        VStack(spacing: 12) {
            Button { model.start() } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: max(18, side * 0.09), weight: .semibold))
                    .foregroundStyle(SteelPalette.background)
                    .frame(width: max(54, side * 0.25), height: max(54, side * 0.25))
                    .background(SteelPalette.ink, in: Circle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            Text("Камера на паузе")
                .font(.headline)
                .foregroundStyle(SteelPalette.ink)
        }
        .multilineTextAlignment(.center)
        .padding(side * 0.16)
    }

    private var missingFaceBubbleState: some View {
        VStack {
            Text(model.frame?.foreignFaceDetected == true ? "Владелец не найден" : "Лицо не найдено")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
            Spacer()
        }
        .multilineTextAlignment(.center)
        .padding(.top, 15)
    }

    private var recognitionOffBubbleState: some View {
        VStack {
            Text("Распознавание выключено")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
            Spacer()
        }
        .multilineTextAlignment(.center)
        .padding(.top, 15)
    }

    private var liveBubbleState: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Circle()
                    .fill(bubbleStateColor)
                    .frame(width: 7, height: 7)
                Text(bubbleStatusTitle)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.9), radius: 4, y: 1)
            .padding(.top, 15)
            Spacer()
            if model.diagnosticsVisible {
                circularMetrics
            }
        }
        .padding(.horizontal, 12)
    }

    private var bubbleStateColor: Color {
        return switch model.glassesState {
        case .unknown: .orange
        case .withGlasses: SteelPalette.ink
        case .withoutGlasses: .white
        }
    }

    private var bubbleStatusTitle: String {
        if !model.recognitionEnabled { return "Распознавание выключено" }
        guard model.measurementReliable else {
            if !model.ownerVerified { return "Другое лицо" }
            if model.decisionMessage.contains("недоступна") { return "Модель недоступна" }
            return model.decisionMessage
        }
        return model.glassesState.title
    }

    private var calibrationCameraOverlay: some View {
        VStack(spacing: 10) {
            Spacer()
            FaceCoverageMap(
                completed: model.completedCalibrationPoses,
                current: model.currentCalibrationPose
            )
            .frame(width: side * 0.50, height: side * 0.59)
            Text(model.currentCalibrationPose?.title ?? "Калибровка завершена")
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(SteelPalette.ink)
            Text("\(model.currentPoseSamples)/\(CalibrationPose.samplesPerPose) кадра")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(SteelPalette.ink)
            Spacer().frame(height: 8)
        }
        .allowsHitTesting(false)
    }

    private var radialControls: some View {
        ZStack {
            RadialActionButton(
                model: model,
                icon: "arrow.up.left.and.arrow.down.right",
                label: model.automaticScaling ? "Выключить автомасштаб" : "Включить автомасштаб",
                active: model.automaticScaling,
                disabled: !model.isCalibrated
            ) {
                guard model.isCalibrated else { return }
                model.automaticScaling.toggle()
                model.saveSettings()
            }
            .position(radialPosition(0))
            RadialActionButton(
                model: model,
                icon: "waveform.path.ecg",
                label: model.diagnosticsVisible ? "Скрыть расчёты" : "Показать расчёты",
                active: model.diagnosticsVisible
            ) {
                model.diagnosticsVisible.toggle()
            }
            .position(radialPosition(1))
            RadialActionButton(model: model, icon: "gearshape", label: "Открыть настройки") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .position(radialPosition(2))
        }
        .frame(width: panelWidth, height: panelHeight)
    }

    private func radialPosition(_ index: Int) -> CGPoint {
        let angle = Double(95 + index * 22) * .pi / 180
        let radius = side / 2 + 25
        let center = CGPoint(x: panelWidth - side / 2, y: side / 2)
        return CGPoint(
            x: center.x + cos(angle) * radius,
            y: center.y + sin(angle) * radius
        )
    }

    private func diagnostics(_ frame: FrameAnalysis) -> some View {
        FaceContourOverlay(frame: frame, tracksFace: true)
    }

    private var circularMetrics: some View {
        Group {
            if hasActiveDecision {
                VStack(spacing: 4) {
                    Text(displayGlassesProbability, format: .percent.precision(.fractionLength(0)))
                        .font(.system(size: side * 0.12, weight: .semibold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                    Text(model.decisionMessage)
                        .font(.caption.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    if model.decisionProgress > 0 {
                        ProgressView(value: model.decisionProgress)
                            .tint(SteelPalette.accentBlue)
                            .frame(width: side * 0.44)
                    }
                    if let neural = model.neuralProbability {
                        Text("модель \(neural, format: .percent.precision(.fractionLength(0))) · итог \(model.probability, format: .percent.precision(.fractionLength(0)))")
                    }
                    if let personal = model.rawPrediction {
                        Text("d(очки) \(personal.glassesDistance, format: .number.precision(.fractionLength(2))) · d(без) \(personal.bareDistance, format: .number.precision(.fractionLength(2)))")
                    }
                    if let frame = model.frame {
                        Text(poseMetrics(frame))
                        if let vector = frame.vector {
                            Text(featureMetrics(vector))
                                .lineLimit(1)
                                .minimumScaleFactor(0.62)
                        }
                    }
                }
            } else {
                VStack(spacing: 4) {
                    Text(model.decisionMessage)
                        .font(.caption.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    if let neural = model.neuralProbability {
                        Text("модель \(neural, format: .percent.precision(.fractionLength(0)))")
                    }
                    if let count = model.frame?.faceCandidates.count, count > 1 {
                        Text("лиц в кадре: \(count)")
                    }
                }
            }
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.white)
        .frame(width: side * 0.68)
        .padding(.bottom, side * 0.08)
        .shadow(color: .black.opacity(0.9), radius: 4, y: 1)
    }

    private var displayGlassesProbability: Double {
        model.rawProbability
    }

    private var decisionConfidence: Double {
        max(model.rawProbability, 1 - model.rawProbability)
    }

    private var hasActiveDecision: Bool {
        model.measurementReliable && model.neuralProbability != nil
    }

    private func poseMetrics(_ frame: FrameAnalysis) -> String {
        let yaw = Int((frame.yaw * 180 / .pi).rounded())
        let roll = Int((frame.roll * 180 / .pi).rounded())
        let pitch = Int((frame.pitch * 180 / .pi).rounded())
        return "yaw \(yaw)° · roll \(roll)° · pitch \(pitch)°"
    }

    private func featureMetrics(_ vector: VisionVector) -> String {
        let values = vector.values.map {
            $0.formatted(.number.precision(.fractionLength(2)))
        }
        return "v [\(values.joined(separator: " · "))]"
    }
}

private struct NativeWindowDragSurface: NSViewRepresentable {
    var passthroughCenter: Bool
    let onFinished: () -> Void

    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        view.onFinished = onFinished
        return view
    }

    func updateNSView(_ view: DragView, context: Context) {
        view.passthroughCenter = passthroughCenter
        view.onFinished = onFinished
    }

    final class DragView: NSView {
        var passthroughCenter = false
        var onFinished: (() -> Void)?
        private var mouseStart: CGPoint?
        private var windowStart: CGPoint?

        override func hitTest(_ point: NSPoint) -> NSView? {
            if passthroughCenter {
                let hole = bounds.insetBy(dx: bounds.width * 0.31, dy: bounds.height * 0.31)
                if hole.contains(point) { return nil }
            }
            return super.hitTest(point)
        }

        override func mouseDown(with event: NSEvent) {
            mouseStart = NSEvent.mouseLocation
            windowStart = window?.frame.origin
            NSCursor.closedHand.set()
        }

        override func mouseDragged(with event: NSEvent) {
            guard let window, let mouseStart, let windowStart else { return }
            let current = NSEvent.mouseLocation
            window.setFrameOrigin(CGPoint(
                x: windowStart.x + current.x - mouseStart.x,
                y: windowStart.y + current.y - mouseStart.y
            ))
        }

        override func mouseUp(with event: NSEvent) {
            mouseStart = nil
            windowStart = nil
            NSCursor.openHand.set()
            onFinished?()
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }
    }
}

struct FaceContourOverlay: View {
    let frame: FrameAnalysis
    var tracksFace = false

    var body: some View {
        Canvas { context, size in
            let imageWidth = CGFloat(frame.imageWidth)
            let imageHeight = CGFloat(frame.imageHeight)
            let baseScale = max(size.width / imageWidth, size.height / imageHeight)
            let zoom = tracksFace
                ? min(1.55, max(1, 0.42 / max(frame.faceRect?.width ?? 0.42, 0.01)))
                : 1
            let scale = baseScale * zoom
            let rendered = CGSize(width: imageWidth * scale, height: imageHeight * scale)
            let faceCenter = CGPoint(
                x: (frame.faceRect?.x ?? 0.5) + (frame.faceRect?.width ?? 0) / 2,
                y: (frame.faceRect?.y ?? 0.5) + (frame.faceRect?.height ?? 0) / 2
            )
            let imageCenter = tracksFace
                ? CGPoint(
                    x: size.width / 2 + (0.5 - faceCenter.x) * rendered.width,
                    y: size.height / 2 + (faceCenter.y - 0.5) * rendered.height
                )
                : CGPoint(x: size.width / 2, y: size.height / 2)
            let offset = CGPoint(x: imageCenter.x - rendered.width / 2, y: imageCenter.y - rendered.height / 2)
            let transform: (NormalizedPoint) -> CGPoint = { point in
                CGPoint(
                    x: offset.x + point.x * rendered.width,
                    y: offset.y + (1 - point.y) * rendered.height
                )
            }
            for candidate in frame.faceCandidates {
                if !candidate.isSelected, candidate.contour.count > 1 {
                    var path = Path()
                    path.move(to: transform(candidate.contour[0]))
                    for point in candidate.contour.dropFirst() { path.addLine(to: transform(point)) }
                    context.stroke(path, with: .color(.white.opacity(0.46)), lineWidth: 1.2)
                }
                let labelPoint = transform(NormalizedPoint(
                    x: candidate.faceRect.x + candidate.faceRect.width / 2,
                    y: candidate.faceRect.y + candidate.faceRect.height
                ))
                let distance = candidate.ownerDistance.map {
                    "d \($0.formatted(.number.precision(.fractionLength(2))))"
                } ?? "лицо"
                let label = candidate.isSelected ? "владелец · \(distance)" : distance
                context.draw(
                    Text(label)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(candidate.isSelected ? SteelPalette.accentBlue : .white.opacity(0.72)),
                    at: CGPoint(x: labelPoint.x, y: labelPoint.y - 8),
                    anchor: .bottom
                )
            }
            for (index, contour) in frame.faceContours.enumerated() where contour.count > 1 {
                if index == 0 {
                    var path = Path()
                    path.move(to: transform(contour[0]))
                    for point in contour.dropFirst() { path.addLine(to: transform(point)) }
                    context.stroke(path, with: .color(SteelPalette.accentBlue), lineWidth: 1.8)
                } else {
                    let diameter = max(2.2, min(size.width, size.height) * 0.009)
                    for point in contour {
                        let mapped = transform(point)
                        let dot = CGRect(
                            x: mapped.x - diameter / 2,
                            y: mapped.y - diameter / 2,
                            width: diameter,
                            height: diameter
                        )
                        context.fill(Path(ellipseIn: dot), with: .color(SteelPalette.ink.opacity(0.92)))
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct FaceTrackedCameraImage: View {
    let image: CGImage
    let frame: FrameAnalysis

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let imageSize = CGSize(width: image.width, height: image.height)
            let baseScale = max(size.width / imageSize.width, size.height / imageSize.height)
            let zoom = min(1.55, max(1, 0.42 / max(frame.faceRect?.width ?? 0.42, 0.01)))
            let rendered = CGSize(
                width: imageSize.width * baseScale * zoom,
                height: imageSize.height * baseScale * zoom
            )
            let faceCenter = CGPoint(
                x: (frame.faceRect?.x ?? 0.5) + (frame.faceRect?.width ?? 0) / 2,
                y: (frame.faceRect?.y ?? 0.5) + (frame.faceRect?.height ?? 0) / 2
            )
            Image(decorative: image, scale: 1)
                .resizable()
                .frame(width: rendered.width, height: rendered.height)
                .position(
                    x: size.width / 2 + (0.5 - faceCenter.x) * rendered.width,
                    y: size.height / 2 + (faceCenter.y - 0.5) * rendered.height
                )
                .animation(.smooth(duration: 0.22), value: faceCenter.x)
                .animation(.smooth(duration: 0.22), value: faceCenter.y)
                .animation(.smooth(duration: 0.22), value: zoom)
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

struct ScaleTransitionView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThickMaterial).ignoresSafeArea()
            Color.black.opacity(0.38).ignoresSafeArea()
            VStack(spacing: 22) {
                ZStack {
                    Circle().stroke(SteelPalette.lineStrong, lineWidth: 1)
                    Circle()
                        .trim(from: 0.08, to: 0.92)
                        .stroke(SteelPalette.ink, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    if model.scaleTransitionState == .withGlasses {
                        SteelIcon(name: "app-eyeglasses", size: 42)
                            .foregroundStyle(SteelPalette.ink)
                    } else {
                        Image(systemName: "textformat.size.larger")
                            .font(.system(size: 34, weight: .medium))
                            .foregroundStyle(SteelPalette.ink)
                    }
                }
                .frame(width: 92, height: 92)

                Text(transitionTitle)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(SteelPalette.ink)
                .multilineTextAlignment(.center)

                Button("Отмена") { model.cancelScaleTransition() }
                    .buttonStyle(.plain)
                    .foregroundStyle(SteelPalette.faint)
                    .pointingHandCursor()
                    .keyboardShortcut(.cancelAction)
            }
            .padding(48)
        }
        .preferredColorScheme(.dark)
    }

    private var transitionTitle: String {
        model.scaleTransitionState == .withoutGlasses
            ? "Без очков. Увеличиваю масштаб"
            : "Очки надеты. Возвращаю масштаб"
    }
}

private struct RadialActionButton: View {
    @ObservedObject var model: AppModel
    let icon: String
    let label: String
    var active = false
    var disabled = false
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            SteelIcon(name: icon, size: 17)
                .foregroundStyle(active ? SteelPalette.background : SteelPalette.ink)
                .frame(width: 40, height: 40)
                .background(active ? SteelPalette.ink : SteelPalette.panel, in: Circle())
                .overlay(Circle().stroke(SteelPalette.lineStrong))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.42 : 1)
        .pointingHandCursor()
        .overlay(alignment: .trailing) {
            if hovered {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SteelPalette.ink)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(SteelPalette.backgroundRaised, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(SteelPalette.lineStrong))
                    .fixedSize()
                    .offset(x: -48)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                    .allowsHitTesting(false)
            }
        }
        .animation(.snappy(duration: 0.2, extraBounce: 0), value: hovered)
        .onHover { value in
            hovered = value
            model.setBubbleHover(value)
        }
        .help(label)
        .accessibilityLabel(label)
    }
}

struct FaceCoverageMap: View {
    let completed: Set<CalibrationPose>
    let current: CalibrationPose?

    private let positions: [(CalibrationPose, CGFloat, CGFloat)] = [
        (.tiltLeft, 0.34, 0.25), (.tiltRight, 0.66, 0.25),
        (.turnLeft, 0.23, 0.49), (.front, 0.50, 0.46), (.turnRight, 0.77, 0.49),
        (.lookDown, 0.50, 0.67),
        (.closer, 0.34, 0.82), (.farther, 0.66, 0.82),
    ]

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                Ellipse()
                    .fill(.black.opacity(0.32))
                    .overlay(Ellipse().stroke(SteelPalette.ink.opacity(0.58), lineWidth: 1.5))
                ForEach(positions, id: \.0) { pose, x, y in
                    let isComplete = completed.contains(pose)
                    let isCurrent = current == pose
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isComplete ? SteelPalette.success : SteelPalette.ink.opacity(isCurrent ? 0.28 : 0.07))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(isCurrent ? SteelPalette.ink : SteelPalette.lineStrong, lineWidth: isCurrent ? 1.5 : 1)
                        }
                        .frame(width: size.width * 0.23, height: size.height * 0.17)
                        .position(x: size.width * x, y: size.height * y)
                }
                Path { path in
                    path.move(to: CGPoint(x: size.width * 0.44, y: size.height * 0.59))
                    path.addQuadCurve(
                        to: CGPoint(x: size.width * 0.56, y: size.height * 0.59),
                        control: CGPoint(x: size.width * 0.50, y: size.height * 0.64)
                    )
                }
                .stroke(SteelPalette.ink.opacity(0.46), lineWidth: 1.2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Покрытие лица: записано \(completed.count) из 8 поз")
    }
}
