import AppKit
import CoreGraphics

enum KeyAction {
    case escape
    case enter
    case space
    case delete
    case digit(Int)
    case other
}

/// 全域事件攔截：
/// - 平常：偵測「連按三下」（clickCount == 3），吞掉第三下並觸發手寫板
/// - 手寫模式：吞掉所有滑鼠/捲動事件（避免手指寫字時誤點），並攔截快捷鍵
final class EventTapManager {
    static let shared = EventTapManager()

    /// 我們自己送出的合成事件會帶這個標記，攔截器會直接放行。
    static let syntheticMarker: Int64 = 0x4857_4954 // "HWIT"

    var triggerEnabled = true
    var writingMode = false {
        didSet { if !writingMode { consumedKeyCodes.removeAll() } }
    }

    var onTripleClick: (() -> Void)?
    var onSingleClickUp: (() -> Void)?
    var onMouseMovedWhileWriting: (() -> Void)?
    /// 回傳 true 表示吞掉這個按鍵。
    var onKey: ((KeyAction) -> Bool)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var swallowNextLeftMouseUp = false
    private var consumedKeyCodes = Set<Int64>()

    var isRunning: Bool { tap != nil }

    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }

        var types: [CGEventType] = [
            .leftMouseDown, .leftMouseUp, .leftMouseDragged,
            .rightMouseDown, .rightMouseUp, .rightMouseDragged,
            .otherMouseDown, .otherMouseUp, .otherMouseDragged,
            .mouseMoved, .scrollWheel, .keyDown, .keyUp,
        ]
        // 觸控板手勢（捏合、旋轉、滑動）NSEventType.gesture = 29, magnify = 30, swipe = 31
        types += [29, 30, 31].compactMap { CGEventType(rawValue: $0) }
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let me = Unmanaged<EventTapManager>.fromOpaque(refcon!).takeUnretainedValue()
            return me.handle(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("[Handwriting] 無法建立事件攔截（需要輔助使用權限）")
            return false
        }
        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker {
            return Unmanaged.passUnretained(event)
        }

        if writingMode {
            return handleWriting(type: type, event: event)
        }

        switch type {
        case .leftMouseDown:
            let clicks = event.getIntegerValueField(.mouseEventClickState)
            if triggerEnabled && clicks == 3 {
                swallowNextLeftMouseUp = true
                DispatchQueue.main.async { [weak self] in self?.onTripleClick?() }
                return nil
            }
        case .leftMouseUp:
            if swallowNextLeftMouseUp {
                swallowNextLeftMouseUp = false
                return nil
            }
            if event.getIntegerValueField(.mouseEventClickState) == 1 {
                onSingleClickUp?()
            }
        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }

    private func handleWriting(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .keyDown:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            let flags = event.flags
            let action: KeyAction
            if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
                action = .other
            } else {
                action = Self.action(for: code)
            }
            if onKey?(action) == true {
                consumedKeyCodes.insert(code)
                return nil
            }
            return Unmanaged.passUnretained(event)
        case .keyUp:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            if consumedKeyCodes.remove(code) != nil { return nil }
            return Unmanaged.passUnretained(event)
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            onMouseMovedWhileWriting?()
            return nil
        case .leftMouseUp:
            swallowNextLeftMouseUp = false
            return nil
        default:
            // 點擊、捲動、手勢一律吞掉，避免寫字時誤觸背景 App
            return nil
        }
    }

    private static func action(for keyCode: Int64) -> KeyAction {
        switch keyCode {
        case 53: return .escape
        case 36, 76: return .enter
        case 49: return .space
        case 51: return .delete
        case 18: return .digit(1)
        case 19: return .digit(2)
        case 20: return .digit(3)
        case 21: return .digit(4)
        case 23: return .digit(5)
        case 22: return .digit(6)
        case 26: return .digit(7)
        case 28: return .digit(8)
        case 25: return .digit(9)
        default: return .other
        }
    }
}
