import AppKit

// Accessory activation policy: Toki lives entirely in its floating panel — no Dock
// icon, no menu bar, and it never activates over whatever you are working in.
let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(.accessory)
application.run()
