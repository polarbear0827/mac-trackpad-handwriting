import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // 只在選單列顯示圖示，不出現在 Dock
app.run()
