import AppKit
import ApplicationServices

/// 把辨識出的文字送進目前游標所在的 App。
/// 使用「剪貼簿 + ⌘V」：對中文、開著注音輸入法的情況都最可靠，送完會還原原本剪貼簿內容。
enum TextInserter {
    private static var restoreWorkItem: DispatchWorkItem?
    private static var savedItems: [[NSPasteboard.PasteboardType: Data]]?

    static func insert(_ text: String) {
        guard !text.isEmpty else { return }
        let pb = NSPasteboard.general

        // 只在「還沒有待還原的備份」時才備份，連續送字時才不會把我們自己的字當成原內容
        if savedItems == nil {
            savedItems = pb.pasteboardItems?.map { item in
                var dict: [NSPasteboard.PasteboardType: Data] = [:]
                for type in item.types {
                    if let data = item.data(forType: type) { dict[type] = data }
                }
                return dict
            } ?? []
        }

        pb.clearContents()
        pb.setString(text, forType: .string)
        postKey(9, flags: .maskCommand) // V

        restoreWorkItem?.cancel()
        let work = DispatchWorkItem { restoreClipboard() }
        restoreWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    static func backspace() {
        postKey(51, flags: [])
    }

    private static func restoreClipboard() {
        guard let items = savedItems else { return }
        savedItems = nil
        let pb = NSPasteboard.general
        pb.clearContents()
        let restored: [NSPasteboardItem] = items.map { dict in
            let item = NSPasteboardItem()
            for (type, data) in dict { item.setData(data, forType: type) }
            return item
        }
        if !restored.isEmpty { pb.writeObjects(restored) }
    }

    private static func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .combinedSessionState)
        for down in [true, false] {
            guard let ev = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: down) else { continue }
            ev.flags = flags
            ev.setIntegerValueField(.eventSourceUserData, value: EventTapManager.syntheticMarker)
            ev.post(tap: .cgSessionEventTap)
        }
    }
}

/// 連按三下時，前兩下會讓 App 選取一個詞。這裡在每次「單擊」後記下游標位置，
/// 觸發手寫板時把選取範圍還原成單純的游標，避免送字時把選起來的詞蓋掉。
final class SelectionRestorer {
    static let shared = SelectionRestorer()

    private let queue = DispatchQueue(label: "handwriting.ax")
    private var saved: (element: AXUIElement, range: CFRange, time: Date)?

    func captureAfterClick() {
        queue.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, let (element, range) = Self.currentSelection() else { return }
            self.saved = (element, range, Date())
        }
    }

    func restoreIfRecent() {
        queue.async { [weak self] in
            guard let self, let saved = self.saved, Date().timeIntervalSince(saved.time) < 2.0 else { return }
            self.saved = nil
            var range = saved.range
            guard let value = AXValueCreate(.cfRange, &range) else { return }
            AXUIElementSetAttributeValue(saved.element, kAXSelectedTextRangeAttribute as CFString, value)
        }
    }

    /// 取得目前焦點文字欄位的插入點位置（螢幕座標，左上原點），找不到就回傳 nil。
    static func caretRect() -> CGRect? {
        guard let (element, range) = currentSelection() else { return nil }
        var r = CFRange(location: range.location, length: 0)
        guard let rangeValue = AXValueCreate(.cfRange, &r) else { return nil }
        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &boundsRef
        ) == .success, let boundsRef, CFGetTypeID(boundsRef) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        AXValueGetValue(boundsRef as! AXValue, .cgRect, &rect)
        return rect.width >= 0 && rect.height > 0 ? rect : nil
    }

    private static func currentSelection() -> (AXUIElement, CFRange)? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.15)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.15)
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        guard AXValueGetValue(rangeRef as! AXValue, .cfRange, &range) else { return nil }
        return (element, range)
    }
}
