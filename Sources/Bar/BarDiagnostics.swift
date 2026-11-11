import AppKit
import VellforgeKit
import ApplicationServices
import BarCore

/// A plain-text report of what Bar can and cannot see.
///
/// Menu bar enumeration depends on undocumented behaviour that varies between
/// macOS releases, and the failure mode is silent: an empty list looks
/// identical whether the permission is missing, the API is unavailable, or
/// there genuinely is nothing there. This makes the difference legible.
@MainActor
enum BarDiagnostics {

    static func report() -> String {
        var out: [String] = []
        func line(_ s: String) { out.append(s) }

        line("BAR")
        line("PERMISSIONS")
        line("  Accessibility:    \(AccessibilityPermission.isTrusted ? "granted" : "NOT granted")")
        line("  Screen Recording: \(ScreenRecordingPermission.isGranted ? "granted" : "NOT granted")")
        line("")

        line("CONTROLCENTER")
        let cc = NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == "com.apple.controlcenter"
        }
        if let cc {
            line("  found, pid \(cc.processIdentifier)")
            let app = AXUIElementCreateApplication(cc.processIdentifier)
            AXUIElementSetMessagingTimeout(app, 1.0)

            var attrNames: CFArray?
            let attrResult = AXUIElementCopyAttributeNames(app, &attrNames)
            let names = (attrNames as? [String]) ?? []
            line("  attribute list: \(attrResult == .success ? "\(names.count) attributes" : "error \(attrResult.rawValue)")")
            if !names.isEmpty {
                line("  attributes: \(names.joined(separator: ", "))")
            }

            var extras: CFTypeRef?
            let extrasResult = AXUIElementCopyAttributeValue(
                app, "AXExtrasMenuBar" as CFString, &extras)
            line("  AXExtrasMenuBar: \(extrasResult == .success ? "available" : "UNAVAILABLE (error \(extrasResult.rawValue))")")

            if extrasResult == .success, let extras,
               CFGetTypeID(extras) == AXUIElementGetTypeID() {
                var kids: CFTypeRef?
                let kidsResult = AXUIElementCopyAttributeValue(
                    extras as! AXUIElement, kAXChildrenAttribute as CFString, &kids)
                let children = (kids as? [AXUIElement]) ?? []
                line("  children: \(kidsResult == .success ? "\(children.count)" : "error \(kidsResult.rawValue)")")
                line("")
                line("RAW CHILDREN (before any filtering)")
                for (i, child) in children.enumerated() {
                    func attr(_ n: String) -> String {
                        var v: CFTypeRef?
                        guard AXUIElementCopyAttributeValue(child, n as CFString, &v) == .success,
                              let v else { return "-" }
                        if let s = v as? String { return s.isEmpty ? "-" : s }
                        if CFGetTypeID(v) == AXValueGetTypeID() {
                            var pt = CGPoint.zero, sz = CGSize.zero
                            if AXValueGetValue(v as! AXValue, .cgPoint, &pt) {
                                return String(format: "(%.0f,%.0f)", pt.x, pt.y)
                            }
                            if AXValueGetValue(v as! AXValue, .cgSize, &sz) {
                                return String(format: "%.0fx%.0f", sz.width, sz.height)
                            }
                        }
                        return "\(v)".prefix(40).description
                    }
                    // Interpolation, not String(format:). `%s` expects a C
                    // string; handing it a Swift String dereferences a garbage
                    // pointer and segfaults — which is exactly what happened.
                    func pad(_ s: String, _ w: Int) -> String {
                        s.count >= w ? s : s + String(repeating: " ", count: w - s.count)
                    }
                    let idx = pad("\(i)", 3)
                    line("  \(idx) pos=\(pad(attr(kAXPositionAttribute as String), 14)) "
                         + "size=\(pad(attr(kAXSizeAttribute as String), 10)) "
                         + "role=\(attr(kAXRoleAttribute as String))")
                    line("        title=\(attr(kAXTitleAttribute as String))  desc=\(attr(kAXDescriptionAttribute as String))  id=\(attr("AXIdentifier"))")
                }
            }
        } else {
            line("  NOT FOUND — cannot enumerate anything")
        }

        line("")
        line("SCANNER RESULT")
        let items = MenuBarScanner.scan()
        line("  items found: \(items.count)")
        for (i, item) in items.enumerated() {
            let x = Int(item.frame.minX), w = Int(item.frame.width)
            line("    \(i)  x=\(x) w=\(w)  \(item.name ?? "(unnamed)")")
        }

        return out.joined(separator: "\n")
    }
}
