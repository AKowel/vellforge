import AppKit
import VellforgeKit
import CoreGraphics
import ScreenCaptureKit
import BarCore

/// Captures the real menu bar icons.
///
/// One screenshot of the whole menu bar strip, then a crop per item — rather
/// than a separate capture per window, which for twenty items would make
/// opening the menu visibly slow.
///
/// Icons are cached, and that matters more than it sounds: a hidden item has
/// been pushed off-screen and cannot be photographed. Capturing whenever the
/// bar is expanded means the dropdown can still show an icon for something
/// currently out of sight.
@MainActor
final class IconCapture {

    private var cache: [UInt32: NSImage] = [:]
    private var lastCapture = Date.distantPast

    /// Don't re-photograph the menu bar more than a few times a second.
    private let minimumInterval: TimeInterval = 0.6

    func image(for windowID: UInt32) -> NSImage? { cache[windowID] }

    var hasIcons: Bool { !cache.isEmpty }

    func refresh(items: [MenuBarItem], force: Bool = false) async {
        guard ScreenRecordingPermission.isGranted, !items.isEmpty else { return }

        let now = Date()
        guard force || now.timeIntervalSince(lastCapture) >= minimumInterval else { return }
        lastCapture = now

        guard let strip = MenuBarScanner.menuBarStrip(for: items),
              strip.width > 0, strip.height > 0,
              let content = try? await SCShareableContent.current,
              let display = content.displays.first
        else { return }

        let scale = NSScreen.main?.backingScaleFactor ?? 2

        let config = SCStreamConfiguration()
        config.sourceRect = strip
        config.width = Int(strip.width * scale)
        config.height = Int(strip.height * scale)
        config.showsCursor = false
        config.captureResolution = .best

        // Exclude our own windows so the separator doesn't photograph itself.
        let filter = SCContentFilter(display: display, excludingApplications: [],
                                     exceptingWindows: [])

        guard let shot = try? await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: config) else { return }

        for item in items {
            // Item coordinates are absolute; the screenshot starts at the strip.
            let relative = CGRect(x: (item.frame.minX - strip.minX) * scale,
                                  y: (item.frame.minY - strip.minY) * scale,
                                  width: item.frame.width * scale,
                                  height: item.frame.height * scale)
            guard relative.width >= 1, relative.height >= 1,
                  let cropped = shot.cropping(to: relative) else { continue }

            cache[item.windowID] = NSImage(cgImage: cropped,
                                           size: NSSize(width: item.frame.width,
                                                        height: item.frame.height))
        }

        // Forget items that have gone away, so the menu never shows a ghost.
        let live = Set(items.map(\.windowID))
        cache = cache.filter { live.contains($0.key) }
    }
}
