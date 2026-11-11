import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Menu bar agent: no Dock icon, no app switcher entry. Mirrors LSUIElement in
// Info.plist, and is what takes effect when running the binary directly.
app.setActivationPolicy(.accessory)
app.run()
