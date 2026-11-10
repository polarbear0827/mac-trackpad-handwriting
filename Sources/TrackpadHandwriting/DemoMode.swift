import AppKit

/// 自我測試（不需要權限）：
/// - `--demo`：開啟手寫板，放入模擬手寫的「中」並辨識，檢查面板外觀
/// - `--test`：用目前的辨識引擎辨識幾個模擬手寫字，印出結果後結束
/// 設定環境變數 DEMO_PNG=路徑 可輸出送進 Vision 的圖片。
enum DemoMode {
    static var isDemo: Bool { CommandLine.arguments.contains("--demo") }
    static var isTest: Bool { CommandLine.arguments.contains("--test") }

    /// 以「字框 0~1」座標、照正確筆順描述的測試字
    static let samples: [(String, [[(CGFloat, CGFloat)]])] = [
        ("中", [
            [(0.12, 0.30), (0.13, 0.50), (0.14, 0.70)],
            [(0.12, 0.30), (0.50, 0.29), (0.88, 0.30), (0.87, 0.50), (0.86, 0.70)],
            [(0.14, 0.68), (0.50, 0.68), (0.86, 0.67)],
            [(0.50, 0.05), (0.50, 0.50), (0.51, 0.95)],
        ]),
        ("人", [
            [(0.50, 0.08), (0.42, 0.50), (0.10, 0.92)],
            [(0.46, 0.42), (0.70, 0.72), (0.92, 0.90)],
        ]),
        ("大", [
            [(0.10, 0.38), (0.50, 0.37), (0.90, 0.36)],
            [(0.50, 0.06), (0.46, 0.50), (0.10, 0.92)],
            [(0.52, 0.46), (0.75, 0.72), (0.93, 0.92)],
        ]),
        ("口", [
            [(0.20, 0.20), (0.21, 0.50), (0.22, 0.85)],
            [(0.20, 0.20), (0.50, 0.20), (0.80, 0.20), (0.79, 0.50), (0.78, 0.85)],
            [(0.22, 0.82), (0.50, 0.82), (0.78, 0.82)],
        ]),
        ("十", [
            [(0.08, 0.46), (0.50, 0.45), (0.92, 0.44)],
            [(0.50, 0.06), (0.50, 0.50), (0.50, 0.95)],
        ]),
        ("王", [
            [(0.18, 0.18), (0.50, 0.18), (0.82, 0.17)],
            [(0.24, 0.50), (0.50, 0.50), (0.76, 0.49)],
            [(0.50, 0.18), (0.50, 0.50), (0.50, 0.86)],
            [(0.10, 0.87), (0.50, 0.86), (0.90, 0.85)],
        ]),
        ("三", [
            [(0.22, 0.18), (0.50, 0.18), (0.78, 0.17)],
            [(0.28, 0.50), (0.50, 0.50), (0.72, 0.49)],
            [(0.10, 0.84), (0.50, 0.83), (0.90, 0.82)],
        ]),
    ]

    /// 把字框座標放到畫布中央，插值成連續取樣點並加一點抖動
    static func strokes(_ spec: [[(CGFloat, CGFloat)]]) -> [Stroke] {
        let size: CGFloat = 0.75
        let ox = (1 - size / trackpadAspect) / 2
        let oy = (1 - size) / 2
        var seed: UInt64 = 7
        func jitter() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            let factor = CGFloat(Double(ProcessInfo.processInfo.environment["DEMO_JITTER"] ?? "") ?? 1)
            return (CGFloat(seed >> 33) / CGFloat(UInt32.max) - 0.5) * 0.008 * factor
        }
        var t: TimeInterval = 0
        return spec.map { pts in
            var out: Stroke = []
            for (a, b) in zip(pts, pts.dropFirst()) {
                for i in 0..<12 {
                    let k = CGFloat(i) / 12
                    let x = a.0 + (b.0 - a.0) * k, y = a.1 + (b.1 - a.1) * k
                    t += 0.01
                    out.append(StrokePoint(x: ox + x * size / trackpadAspect + jitter(), y: oy + y * size + jitter(), t: t))
                }
            }
            let last = pts.last!
            out.append(StrokePoint(x: ox + last.0 * size / trackpadAspect, y: oy + last.1 * size, t: t))
            t += 0.3
            return out
        }
    }
}

extension HandwritingController {
    /// 顯示示範筆畫並辨識，結果印到 stdout
    func runDemo() {
        open()
        EventTapManager.shared.writingMode = false
        CGAssociateMouseAndMouseCursorPosition(1)
        model.strokes = DemoMode.strokes(DemoMode.samples[0].1)
        let strokes = model.strokes
        let recognizer = self.recognizer

        if let out = ProcessInfo.processInfo.environment["DEMO_PNG"], let img = VisionRecognizer.render(strokes) {
            let rep = NSBitmapImageRep(cgImage: img)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
        }
        Task { @MainActor in
            do {
                let result = try await recognizer.recognize(strokes)
                self.model.candidates = result
                print("DEMO 辨識結果：\(result)")
            } catch {
                print("DEMO 辨識失敗：\(error)")
            }
            for w in NSApp.windows where w is HandwritingPanel {
                print("panel frame:", w.frame, "windowNumber:", w.windowNumber)
            }
            fflush(stdout)
        }
    }

    /// 逐一辨識測試字，印出前幾名候選後結束程式
    func runTest() {
        let recognizer = self.recognizer
        Task { @MainActor in
            var correct = 0
            for (expected, spec) in DemoMode.samples {
                let start = Date()
                let result = (try? await recognizer.recognize(DemoMode.strokes(spec))) ?? []
                let ms = Int(Date().timeIntervalSince(start) * 1000)
                let ok = result.first == expected
                if ok { correct += 1 }
                print("\(ok ? "✓" : "✗") \(expected) → \(result.prefix(6).joined(separator: " "))  (\(ms) ms)")
            }
            print("[\(recognizer.displayName)] 第一候選正確：\(correct)/\(DemoMode.samples.count)")
            fflush(stdout)
            exit(0)
        }
    }
}
