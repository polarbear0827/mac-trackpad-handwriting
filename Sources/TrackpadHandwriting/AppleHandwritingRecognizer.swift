import Foundation
import CAppleHandwriting

/// Apple 內建的手寫引擎（iPad Scribble、備忘錄手寫用的同一套），完全離線、以筆畫辨識。
/// 系統裡找不到這個引擎時，自動改用 Vision。
struct AppleHandwritingRecognizer: HandwritingRecognizer {
    var displayName: String { AHIsAvailable() ? "Apple 手寫引擎" : "Apple Vision（備援）" }
    var localeIdentifier = "zh_TW"

    private let fallback = VisionRecognizer()

    /// App 啟動時先在背景建立辨識器（載入模型），第一次寫字就不用等
    static func preload() {
        DispatchQueue.global(qos: .utility).async {
            let p = StrokePoint(x: 0.5, y: 0.5, t: 0)
            _ = try? AppleHandwritingRecognizer.classify([[p, p]], locale: "zh_TW")
        }
    }

    func recognize(_ strokes: [Stroke]) async throws -> [String] {
        guard AHIsAvailable() else { return try await fallback.recognize(strokes) }
        return try Self.classify(strokes, locale: localeIdentifier)
    }

    static func classify(_ strokes: [Stroke], locale: String) throws -> [String] {
        // 觸控板 0~1 座標 → 約 300pt 高的畫布（y 向下），寬度照觸控板比例
        let scale: Double = 300
        var xs: [Double] = []
        var ys: [Double] = []
        var ends: [Int] = []
        for stroke in strokes where !stroke.isEmpty {
            for p in stroke {
                xs.append(Double(p.x * trackpadAspect) * scale)
                ys.append(Double(p.y) * scale)
            }
            ends.append(xs.count)
        }
        guard !ends.isEmpty else { return [] }

        let result = xs.withUnsafeBufferPointer { xp in
            ys.withUnsafeBufferPointer { yp in
                ends.withUnsafeBufferPointer { ep in
                    AHRecognize(xp.baseAddress!, yp.baseAddress!, ep.baseAddress!, ends.count, locale, 9)
                }
            }
        }
        guard let result else {
            throw NSError(domain: "AppleHandwriting", code: 1, userInfo: [NSLocalizedDescriptionKey: "系統手寫引擎無法使用"])
        }
        return result
    }
}
