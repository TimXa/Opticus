import AppKit
import CoreText
import QuartzCore
import SwiftUI

@main
struct OpticusApp: App {
    @StateObject private var model = AppModel()

    init() {
        if let fontURL = Bundle.module.url(forResource: "DaysOne-Regular", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
        }
    }

    var body: some Scene {
        Settings {
            SettingsView(model: model)
        }
        .defaultSize(width: 750, height: 500)

        MenuBarExtra("Opticus", systemImage: "eyeglasses") {
            Text(model.glassesState.title)
            Divider()
            Toggle("Показывать кружок", isOn: Binding(
                get: { model.bubbleVisible },
                set: { model.setBubbleVisible($0) }
            ))
            Toggle("Показать расчёты", isOn: $model.diagnosticsVisible)
            Toggle("Автоматически менять масштаб", isOn: Binding(
                get: { model.automaticScaling },
                set: { model.automaticScaling = $0; model.saveSettings() }
            ))
            .disabled(!model.isCalibrated)
            Divider()
            SettingsLink { Text("Настройки…") }
            Button("Завершить Opticus") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}

@MainActor
enum BubbleResizeAnchor {
    case topRight
    case topLeft
    case bottomRight
}

@MainActor
final class BubblePanel {
    static let shared = BubblePanel()
    private var panel: NSPanel?
    private var lastCircleCenterOnScreen: CGPoint?

    func show(model: AppModel) {
        if panel == nil {
            let panel = NSPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isMovable = true
            panel.isMovableByWindowBackground = false
            panel.contentViewController = NSHostingController(rootView: CameraBubbleView(model: model))
            self.panel = panel
        }
        placePanel(side: model.bubbleSize)
        panel?.orderFrontRegardless()
    }

    func hide() {
        if let panel {
            let side = panel.frame.height - 90
            lastCircleCenterOnScreen = CGPoint(
                x: panel.frame.maxX - side / 2,
                y: panel.frame.maxY - side / 2
            )
        }
        panel?.orderOut(nil)
        panel?.contentViewController = nil
        panel = nil
    }

    var circleCenterOnScreen: CGPoint? {
        guard let panel else { return lastCircleCenterOnScreen }
        let side = panel.frame.height - 90
        return CGPoint(
            x: panel.frame.maxX - side / 2,
            y: panel.frame.maxY - side / 2
        )
    }

    func finishMove() {
        guard let origin = panel?.frame.origin else { return }
        UserDefaults.standard.set(origin.x, forKey: "bubbleOriginX")
        UserDefaults.standard.set(origin.y, forKey: "bubbleOriginY")
    }

    func resize(for side: CGFloat, anchor: BubbleResizeAnchor) {
        guard let panel else { return }
        let oldFrame = panel.frame
        let oldSide = oldFrame.height - 90
        let oldCircleLeft = oldFrame.maxX - oldSide
        let oldCircleBottom = oldFrame.maxY - oldSide
        let size = panelSize(for: side)
        let newMaxX: CGFloat
        let newMaxY: CGFloat
        switch anchor {
        case .topRight:
            newMaxX = oldFrame.maxX
            newMaxY = oldFrame.maxY
        case .topLeft:
            newMaxX = oldCircleLeft + side
            newMaxY = oldFrame.maxY
        case .bottomRight:
            newMaxX = oldFrame.maxX
            newMaxY = oldCircleBottom + side
        }
        let origin = CGPoint(x: newMaxX - size.width, y: newMaxY - size.height)
        panel.setFrame(CGRect(origin: origin, size: size), display: false)
        constrainToVisibleScreen()
    }

    private func panelSize(for side: CGFloat) -> CGSize {
        CGSize(width: side + 230, height: side + 90)
    }

    private func placePanel(side: CGFloat) {
        guard let panel, let screen = panel.screen ?? NSScreen.main else { return }
        let size = panelSize(for: side)
        let defaults = UserDefaults.standard
        let hasSavedOrigin = defaults.object(forKey: "bubbleOriginX") != nil
        let origin = hasSavedOrigin
            ? CGPoint(x: defaults.double(forKey: "bubbleOriginX"), y: defaults.double(forKey: "bubbleOriginY"))
            : CGPoint(
                x: screen.visibleFrame.maxX - size.width - 24,
                y: screen.visibleFrame.maxY - size.height - 24
            )
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
        constrainToVisibleScreen()
    }

    private func constrainToVisibleScreen() {
        guard let panel, let screen = panel.screen ?? NSScreen.main else { return }
        let bounds = screen.visibleFrame
        let origin = CGPoint(
            x: min(max(panel.frame.minX, bounds.minX), bounds.maxX - panel.frame.width),
            y: min(max(panel.frame.minY, bounds.minY), bounds.maxY - panel.frame.height)
        )
        panel.setFrameOrigin(origin)
    }
}

private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class CalibrationWindow {
    static let shared = CalibrationWindow()
    private var panel: NSPanel?

    func show(model: AppModel) {
        BubblePanel.shared.hide()
        let screen = NSScreen.main ?? NSScreen.screens[0]
        if panel == nil {
            let panel = KeyablePanel(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentViewController = NSHostingController(
                rootView: CalibrationExperienceView(model: model)
            )
            self.panel = panel
        }
        panel?.setFrame(screen.frame, display: true)
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
    }

    func dismiss(model: AppModel) {
        guard let panel else {
            model.applyBubbleVisibility()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.38
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in
                panel.orderOut(nil)
                panel.alphaValue = 1
                model.applyBubbleVisibility()
            }
        })
    }
}

@MainActor
final class ScaleTransitionWindow {
    static let shared = ScaleTransitionWindow()
    private var panel: NSPanel?

    func show(model: AppModel) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        if panel == nil {
            let panel = KeyablePanel(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .statusBar
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentViewController = NSHostingController(
                rootView: ScaleTransitionView(model: model)
            )
            self.panel = panel
        }
        panel?.setFrame(screen.frame, display: true)
        panel?.alphaValue = 0
        panel?.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel?.animator().alphaValue = 1
        }
    }

    func fillCurrentScreen() {
        let screen = panel?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        panel?.setFrame(screen.frame, display: true, animate: false)
    }

    func dismiss() {
        guard let panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: {
            Task { @MainActor in panel.orderOut(nil) }
        })
    }
}
