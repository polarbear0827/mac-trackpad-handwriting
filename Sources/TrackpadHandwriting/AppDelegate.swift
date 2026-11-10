import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var controller: HandwritingController!
    private var permissionTimer: Timer?
    private let defaults = UserDefaults.standard

    private var engine: RecognizerEngine {
        get { RecognizerEngine(rawValue: defaults.string(forKey: "engine.v2") ?? "") ?? .apple }
        set { defaults.set(newValue.rawValue, forKey: "engine.v2"); controller.recognizer = newValue.make() }
    }

    private var triggerEnabled: Bool {
        get { defaults.object(forKey: "triggerEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "triggerEnabled"); EventTapManager.shared.triggerEnabled = newValue }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = HandwritingController()
        controller.recognizer = engine.make()
        AppleHandwritingRecognizer.preload()
        EventTapManager.shared.triggerEnabled = triggerEnabled

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pencil.and.scribble", accessibilityDescription: "觸控板手寫")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        if DemoMode.isTest {
            let args = CommandLine.arguments
            if let i = args.firstIndex(of: "--engine"), i + 1 < args.count, let e = RecognizerEngine(rawValue: args[i + 1]) {
                controller.recognizer = e.make()
            }
            controller.runTest()
            return
        }
        if DemoMode.isDemo {
            controller.runDemo()
            return
        }

        MultitouchManager.shared.start()
        startEventTapWhenTrusted()
    }

    /// 需要「輔助使用」權限才能攔截點擊與送出文字；沒有權限就提示並每 2 秒重試
    private func startEventTapWhenTrusted() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(opts), EventTapManager.shared.start() { return }
        permissionTimer = .scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            if AXIsProcessTrusted(), EventTapManager.shared.start() {
                timer.invalidate()
                self?.permissionTimer = nil
            }
        }
    }

    // MARK: - 選單

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let trusted = AXIsProcessTrusted() && EventTapManager.shared.isRunning
        let status = NSMenuItem(title: trusted ? "✓ 已就緒：連按觸控板三下開始手寫" : "⚠︎ 需要輔助使用權限", action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        if MultitouchManager.shared.deviceCount <= 0 {
            let warn = NSMenuItem(title: "⚠︎ 找不到觸控板裝置", action: nil, keyEquivalent: "")
            warn.isEnabled = false
            menu.addItem(warn)
        }
        menu.addItem(.separator())

        menu.addItem(item("開啟手寫板", #selector(openPanel)))

        let trigger = item("連按觸控板三下開啟", #selector(toggleTrigger))
        trigger.state = triggerEnabled ? .on : .off
        menu.addItem(trigger)

        let engineMenu = NSMenu()
        for e in RecognizerEngine.allCases {
            let mi = item(e.title, #selector(selectEngine(_:)))
            mi.representedObject = e.rawValue
            mi.state = e == engine ? .on : .off
            engineMenu.addItem(mi)
        }
        let engineItem = NSMenuItem(title: "辨識引擎", action: nil, keyEquivalent: "")
        engineItem.submenu = engineMenu
        menu.addItem(engineItem)

        menu.addItem(.separator())
        menu.addItem(item("打開輔助使用權限設定…", #selector(openAccessibilitySettings)))
        menu.addItem(.separator())
        menu.addItem(item("結束", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let mi = NSMenuItem(title: title, action: action, keyEquivalent: key)
        mi.target = self
        return mi
    }

    @objc private func openPanel() {
        // 等選單收起再開，避免點選單的那一下被當成筆畫
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.controller.open() }
    }

    @objc private func toggleTrigger() { triggerEnabled.toggle() }

    @objc private func selectEngine(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let e = RecognizerEngine(rawValue: raw) else { return }
        if e == .google {
            let alert = NSAlert()
            alert.messageText = "改用 Google 線上辨識？"
            alert.informativeText = "辨識時會把你的手寫筆畫座標傳送到 Google 的伺服器（inputtools.google.com）。這是非官方介面，隨時可能失效。準確度通常比裝置端好很多。"
            alert.addButton(withTitle: "使用 Google")
            alert.addButton(withTitle: "取消")
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        engine = e
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func quit() {
        controller.close(commit: false)
        MultitouchManager.shared.stop()
        NSApp.terminate(nil)
    }
}
