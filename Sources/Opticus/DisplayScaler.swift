import AppKit
import CoreGraphics

struct DisplayModeOption: Identifiable, Hashable, Sendable {
    let id: String
    let width: Int
    let height: Int
    let pixelWidth: Int
    let pixelHeight: Int

    var title: String {
        let scale = Double(pixelWidth) / Double(max(width, 1))
        return "\(width) × \(height) точек · Retina \(String(format: "%.0f", scale * 100))%"
    }
}

@MainActor
final class DisplayScaler {
    private(set) var modes: [DisplayModeOption] = []
    private var nativeModes: [String: CGDisplayMode] = [:]
    let displayID: CGDirectDisplayID

    init(displayID: CGDirectDisplayID = CGMainDisplayID()) {
        self.displayID = displayID
        reload()
    }

    func reload() {
        let options: [CFString: Any] = [kCGDisplayShowDuplicateLowResolutionModes: true]
        let candidates = (CGDisplayCopyAllDisplayModes(displayID, options as CFDictionary) as? [CGDisplayMode]) ?? []
        let aspect = Double(CGDisplayPixelsWide(displayID)) / Double(CGDisplayPixelsHigh(displayID))
        let filtered = candidates.filter { mode in
            guard mode.width >= 960, mode.height >= 600 else { return false }
            return abs(Double(mode.width) / Double(mode.height) - aspect) < 0.04
        }

        var unique: [String: CGDisplayMode] = [:]
        for mode in filtered {
            let key = Self.key(for: mode)
            if unique[key] == nil || mode.pixelWidth > unique[key]!.pixelWidth {
                unique[key] = mode
            }
        }
        nativeModes = unique
        modes = unique.values.map { mode in
            DisplayModeOption(
                id: Self.key(for: mode), width: mode.width, height: mode.height,
                pixelWidth: mode.pixelWidth, pixelHeight: mode.pixelHeight
            )
        }.sorted { $0.width < $1.width }
    }

    var currentModeID: String? {
        CGDisplayCopyDisplayMode(displayID).map(Self.key(for:))
    }

    func apply(modeID: String) throws {
        guard let mode = nativeModes[modeID] else { throw ScaleError.modeUnavailable }
        let result = CGDisplaySetDisplayMode(displayID, mode, nil)
        guard result == .success else { throw ScaleError.coreGraphics(result.rawValue) }
    }

    private static func key(for mode: CGDisplayMode) -> String {
        "\(mode.width)x\(mode.height)-\(mode.pixelWidth)x\(mode.pixelHeight)-\(mode.ioDisplayModeID)"
    }
}

enum ScaleError: LocalizedError {
    case modeUnavailable
    case coreGraphics(Int32)

    var errorDescription: String? {
        switch self {
        case .modeUnavailable: "Этот режим экрана больше недоступен."
        case .coreGraphics(let code): "macOS отклонила режим экрана (CGError \(code))."
        }
    }
}
