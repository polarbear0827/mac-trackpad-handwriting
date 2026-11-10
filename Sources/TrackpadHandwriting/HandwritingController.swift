import AppKit
import ApplicationServices

/// 手寫流程：開關面板、把觸控板觸控轉成筆畫、停筆後辨識、自動送字。
final class HandwritingController {
    // 時間參數（秒）
    private let recognizeDelay: TimeInterval = 0.45  // 停筆多久開始辨識（先顯示候選）
    private let commitDelay: TimeInterval = 1.3      // 停筆多久自動送出第一候選
    private let idleCloseDelay: TimeInterval = 12    // 多久沒動作自動關閉
    private let twoFingerTapMax: TimeInterval = 0.35

    let model = HandwritingModel()
    var recognizer: HandwritingRecognizer = VisionRecognizer() {
        didSet { model.engineName = recognizer.displayName }
    }

    private(set) var isOpen = false
    private var panel: HandwritingPanel?
    private var savedCursor: CGPoint?

    // 觸控狀態
    private var trackedID: Int32?
    private var ignoreUntilAllUp = false
    private var gestureActive = false
    private var gestureStart: TimeInterval = 0
    private var gestureMaxFingers = 0

    // 辨識狀態
    private var inkGeneration = 0
    private var commitWhenReady = false
    private var recognizeTimer: Timer?
    private var commitTimer: Timer?
    private var idleTimer: Timer?

    init() {
        model.engineName = recognizer.displayName
        MultitouchManager.shared.onFrame = { [weak self] samples, ts in self?.handleFrame(samples, ts) }

        let tap = EventTapManager.shared
        tap.onTripleClick = { [weak self] in self?.toggle() }
        tap.onSingleClickUp = { SelectionRestorer.shared.captureAfterClick() }
        tap.onKey = { [weak self] action in self?.handleKey(action) ?? false }
        tap.onMouseMovedWhileWriting = { [weak self] in
            if let p = self?.savedCursor { CGWarpMouseCursorPosition(p) }
        }
    }

    func toggle() { isOpen ? close(commit: true) : open() }

    // MARK: - 開啟 / 關閉

    func open() {
        guard !isOpen else { return }
        isOpen = true

        SelectionRestorer.shared.restoreIfRecent()
        model.reset()
        model.engineName = recognizer.displayName
        savedCursor = CGEvent(source: nil)?.location

        let panel = HandwritingPanel(model: model)
        panel.setFrameOrigin(panelOrigin(for: panel.frame.size))
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        self.panel = panel

        trackedID = nil
        gestureActive = false
        ignoreUntilAllUp = true          // 等觸發的那根手指離開再開始收筆畫
        EventTapManager.shared.writingMode = true
        CGAssociateMouseAndMouseCursorPosition(0) // 寫字時游標不動
        bumpIdle()
    }

    func close(commit: Bool) {
        guard isOpen else { return }
        if commit { commitPendingForClose() }
        isOpen = false

        [recognizeTimer, commitTimer, idleTimer].forEach { $0?.invalidate() }
        EventTapManager.shared.writingMode = false
        if let p = savedCursor { CGWarpMouseCursorPosition(p) }
        CGAssociateMouseAndMouseCursorPosition(1)

        if let panel {
            self.panel = nil
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.18
                panel.animator().alphaValue = 0
            }, completionHandler: { panel.orderOut(nil) })
        }
    }

    /// 面板放在輸入游標下方；拿不到游標位置就放在滑鼠附近
    private func panelOrigin(for size: NSSize) -> NSPoint {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let anchor: NSRect
        if let caret = SelectionRestorer.caretRect() {
            anchor = NSRect(x: caret.minX, y: primaryHeight - caret.maxY, width: max(caret.width, 1), height: caret.height)
        } else {
            let m = NSEvent.mouseLocation
            anchor = NSRect(x: m.x, y: m.y, width: 1, height: 1)
        }
        let screen = NSScreen.screens.first { $0.frame.contains(anchor.origin) } ?? NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame

        var x = anchor.midX - size.width / 2
        var y = anchor.minY - size.height - 4
        if y < vf.minY { y = anchor.maxY + 4 }                 // 下方放不下就放上方
        x = min(max(x, vf.minX), vf.maxX - size.width)
        y = min(max(y, vf.minY), vf.maxY - size.height)
        return NSPoint(x: x, y: y)
    }

    // MARK: - 觸控 → 筆畫

    private func handleFrame(_ samples: [TouchSample], _ ts: TimeInterval) {
        guard isOpen else { return }
        let touching = samples.filter(\.touching)

        if ignoreUntilAllUp {
            if touching.isEmpty { ignoreUntilAllUp = false }
            return
        }
        if !touching.isEmpty { bumpIdle() }

        // 兩根以上手指：視為手勢（雙指輕點 = 刪除上一筆）
        if touching.count >= 2 || gestureActive {
            if !gestureActive {
                gestureActive = true
                gestureStart = ts
                gestureMaxFingers = 0
                if trackedID != nil { // 放棄剛開始的那一筆
                    trackedID = nil
                    model.currentStroke = []
                }
            }
            gestureMaxFingers = max(gestureMaxFingers, touching.count)
            model.fingerPosition = nil
            if touching.isEmpty {
                gestureActive = false
                if ts - gestureStart < twoFingerTapMax && gestureMaxFingers == 2 { undoLastStroke() }
            }
            return
        }

        guard let finger = touching.first else {
            model.fingerPosition = nil
            if trackedID != nil { endStroke() }
            return
        }

        let p = StrokePoint(x: finger.x, y: 1 - finger.y, t: ts)
        model.fingerPosition = CGPoint(x: p.x, y: p.y)

        if trackedID != finger.id {
            if trackedID != nil { endStroke() }
            beginStroke(id: finger.id, at: p)
        } else if let last = model.currentStroke.last, hypot(last.x - p.x, last.y - p.y) > 0.0015 {
            model.currentStroke.append(p)
        }
    }

    private func beginStroke(id: Int32, at p: StrokePoint) {
        trackedID = id
        recognizeTimer?.invalidate()
        commitTimer?.invalidate()
        commitWhenReady = false
        inkGeneration += 1
        // 在自動送出前接著寫 → 視為同一段字，先清掉預覽候選
        model.candidates = []
        model.alternates = []
        model.lastCommitted = nil
        model.statusMessage = nil
        model.isRecognizing = false
        model.currentStroke = [p]
    }

    private func endStroke() {
        trackedID = nil
        if !model.currentStroke.isEmpty {
            model.strokes.append(model.currentStroke)
        }
        model.currentStroke = []
        scheduleRecognition()
    }

    private func undoLastStroke() {
        guard !model.strokes.isEmpty else { return }
        model.strokes.removeLast()
        inkGeneration += 1
        model.candidates = []
        commitWhenReady = false
        recognizeTimer?.invalidate()
        commitTimer?.invalidate()
        if !model.strokes.isEmpty { scheduleRecognition() }
    }

    // MARK: - 辨識 / 送出

    private func scheduleRecognition() {
        recognizeTimer?.invalidate()
        commitTimer?.invalidate()
        guard !model.strokes.isEmpty else { return }
        recognizeTimer = .scheduledTimer(withTimeInterval: recognizeDelay, repeats: false) { [weak self] _ in
            self?.runRecognition()
        }
        commitTimer = .scheduledTimer(withTimeInterval: commitDelay, repeats: false) { [weak self] _ in
            self?.autoCommit()
        }
    }

    private func runRecognition() {
        let strokes = model.strokes
        guard !strokes.isEmpty else { return }
        let gen = inkGeneration
        let recognizer = self.recognizer
        model.isRecognizing = true

        Task { @MainActor [weak self] in
            let result: Result<[String], Error>
            do { result = .success(try await recognizer.recognize(strokes)) }
            catch { result = .failure(error) }

            guard let self, gen == self.inkGeneration else { return }
            self.model.isRecognizing = false
            switch result {
            case .success(let candidates):
                self.model.candidates = candidates
                self.model.statusMessage = candidates.isEmpty ? "無法辨識，請再寫一次" : nil
            case .failure(let error):
                self.model.candidates = []
                self.model.statusMessage = "辨識失敗：\(error.localizedDescription)"
            }
            if self.commitWhenReady {
                self.commitWhenReady = false
                self.autoCommit()
            }
        }
    }

    private func autoCommit() {
        if !model.candidates.isEmpty {
            commit(index: 0)
        } else if model.isRecognizing {
            commitWhenReady = true
        } else if !model.strokes.isEmpty {
            clearInk() // 辨識不出來：清空畫布讓使用者重寫
        }
    }

    private func commit(index: Int) {
        guard index < model.candidates.count else { return }
        let text = model.candidates[index]
        TextInserter.insert(text)

        var alts = model.candidates
        alts.swapAt(0, index)
        model.lastCommitted = text
        model.alternates = alts
        model.candidates = []
        clearInk()
    }

    /// 已送出後，用數字鍵替換成其他候選
    private func replaceCommitted(with index: Int) {
        guard let last = model.lastCommitted, index < model.alternates.count else { return }
        let text = model.alternates[index]
        guard text != last else { return }
        for _ in 0..<last.count { TextInserter.backspace() }
        TextInserter.insert(text)
        model.alternates.swapAt(0, index)
        model.lastCommitted = text
    }

    private func clearInk() {
        inkGeneration += 1
        recognizeTimer?.invalidate()
        commitTimer?.invalidate()
        model.strokes = []
        model.currentStroke = []
    }

    /// 關閉面板時，把還沒送出的字送出去（可能需要先等辨識完成）
    private func commitPendingForClose() {
        if !model.candidates.isEmpty {
            commit(index: 0)
            return
        }
        let strokes = model.strokes
        guard !strokes.isEmpty else { return }
        let recognizer = self.recognizer
        inkGeneration += 1
        Task { @MainActor in
            if let best = try? await recognizer.recognize(strokes).first {
                TextInserter.insert(best)
            }
        }
    }

    // MARK: - 鍵盤

    private func handleKey(_ action: KeyAction) -> Bool {
        bumpIdle()
        switch action {
        case .escape:
            close(commit: false)
            return true
        case .enter:
            close(commit: true)
            return true
        case .space:
            if !model.candidates.isEmpty { commit(index: 0); return true }
            if !model.strokes.isEmpty { commitWhenReady = true; runRecognition(); return true }
            return false // 沒有待送出的字 → 直接輸入空白
        case .delete:
            if model.hasInk { undoLastStroke(); return true }
            model.alternates = []
            model.lastCommitted = nil
            return false // 交給 App 刪除前一個字
        case .digit(let n):
            if !model.candidates.isEmpty {
                commit(index: n - 1)
                return true
            }
            if !model.alternates.isEmpty {
                replaceCommitted(with: n - 1)
                return true
            }
            return false
        case .other:
            close(commit: true)
            return false // 其他按鍵：關閉手寫板並照常輸入
        }
    }

    private func bumpIdle() {
        idleTimer?.invalidate()
        idleTimer = .scheduledTimer(withTimeInterval: idleCloseDelay, repeats: false) { [weak self] _ in
            self?.close(commit: true)
        }
    }
}
