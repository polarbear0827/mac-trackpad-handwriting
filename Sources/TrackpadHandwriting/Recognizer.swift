import AppKit
import Vision

protocol HandwritingRecognizer {
    var displayName: String { get }
    /// 回傳候選字串（最可能的排第一）
    func recognize(_ strokes: [Stroke]) async throws -> [String]
}

enum RecognizerEngine: String, CaseIterable {
    case apple
    case vision
    case google

    var title: String {
        switch self {
        case .apple: return "Apple 手寫引擎（離線，推薦）"
        case .vision: return "Apple Vision（離線，圖片辨識，較不準）"
        case .google: return "Google 手寫辨識（線上）"
        }
    }

    func make() -> HandwritingRecognizer {
        switch self {
        case .apple: return AppleHandwritingRecognizer()
        case .vision: return VisionRecognizer()
        case .google: return GoogleRecognizer()
        }
    }
}

// MARK: - Apple Vision：把筆畫畫成圖片後做文字辨識，完全在本機執行

struct VisionRecognizer: HandwritingRecognizer {
    let displayName = "Apple Vision"

    /// Vision 對「字在圖中的大小」很敏感：同一個字在某些尺寸讀得到、某些讀不到。
    /// 所以用幾種小尺寸各畫一張，平行辨識後投票排序，也順便得到多個候選字。
    private static let variants: [(canvas: CGFloat, fraction: CGFloat)] = [
        (160, 0.35), (160, 0.7), (200, 0.55), (240, 0.25), (240, 0.5), (240, 0.85),
    ]

    func recognize(_ strokes: [Stroke]) async throws -> [String] {
        let images = Self.variants.compactMap { Self.render(strokes, canvas: $0.canvas, fraction: $0.fraction) }
        guard !images.isEmpty else { return [] }

        let results = await withTaskGroup(of: [String].self) { group in
            for image in images {
                group.addTask { Self.recognizeImage(image) }
            }
            var all: [[String]] = []
            for await r in group { all.append(r) }
            return all
        }

        // 投票：各版本第一名 3 分、第二名 2 分、其他 1 分
        var score: [String: Int] = [:]
        var order: [String] = []
        for list in results {
            for (rank, text) in list.enumerated() {
                if score[text] == nil { order.append(text) }
                score[text, default: 0] += rank == 0 ? 3 : (rank == 1 ? 2 : 1)
            }
        }
        return order.sorted { score[$0]! > score[$1]! }
    }

    private static func recognizeImage(_ image: CGImage) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        let wanted = ["zh-Hant", "zh-Hans", "en-US"]
        let supported = (try? request.supportedRecognitionLanguages()) ?? wanted
        request.recognitionLanguages = wanted.filter { supported.contains($0) }
        do {
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        } catch {
            return []
        }
        let observations = (request.results ?? []).sorted { $0.boundingBox.minX < $1.boundingBox.minX }
        return combine(observations)
    }

    /// 多個文字區塊時，把每個區塊同一名次的候選串起來
    private static func combine(_ observations: [VNRecognizedTextObservation]) -> [String] {
        let lists = observations.map { $0.topCandidates(5).map { $0.string.trimmingCharacters(in: .whitespaces) } }
            .filter { !$0.isEmpty }
        guard !lists.isEmpty else { return [] }
        let maxCount = lists.map(\.count).max() ?? 0
        var results: [String] = []
        for i in 0..<maxCount {
            let s = lists.map { i < $0.count ? $0[i] : $0[0] }.joined()
            if !s.isEmpty && !results.contains(s) { results.append(s) }
        }
        return results
    }

    /// 將筆畫裁切到邊界、等比例縮放成「長邊 = canvas × fraction」，白底黑字畫成圖片
    static func render(_ strokes: [Stroke], canvas: CGFloat = 240, fraction: CGFloat = 0.5) -> CGImage? {
        let pts = strokes.flatMap { $0 }.map { CGPoint(x: $0.x * trackpadAspect, y: $0.y) }
        guard let minX = pts.map(\.x).min(), let maxX = pts.map(\.x).max(),
              let minY = pts.map(\.y).min(), let maxY = pts.map(\.y).max() else { return nil }

        let inkW = max(maxX - minX, 0.02)
        let inkH = max(maxY - minY, 0.02)
        let target = canvas * fraction
        // 多字橫寫時以高度為準，避免整行被縮得太小
        let scale = target / (inkW > inkH * 1.8 ? inkH : max(inkW, inkH))
        let width = Int(max(canvas, inkW * scale + canvas * (1 - fraction)))
        let height = Int(max(canvas, inkH * scale + canvas * (1 - fraction)))
        let offsetX = (CGFloat(width) - inkW * scale) / 2
        let offsetY = (CGFloat(height) - inkH * scale) / 2
        let lineWidth = max(2, target * 0.06)

        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setStrokeColor(gray: 0, alpha: 1)
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        func map(_ p: StrokePoint) -> CGPoint {
            let x = (p.x * trackpadAspect - minX) * scale + offsetX
            let y = (p.y - minY) * scale + offsetY
            return CGPoint(x: x, y: CGFloat(height) - y) // CGContext 原點在左下
        }

        for stroke in strokes {
            guard let first = stroke.first else { continue }
            ctx.beginPath()
            ctx.move(to: map(first))
            if stroke.count == 1 {
                let p = map(first)
                ctx.addLine(to: CGPoint(x: p.x + 0.5, y: p.y))
            } else {
                for p in stroke.dropFirst() { ctx.addLine(to: map(p)) }
            }
            ctx.strokePath()
        }
        return ctx.makeImage()
    }
}

// MARK: - Google 線上手寫辨識（會把筆畫座標送到 Google，預設關閉）

struct GoogleRecognizer: HandwritingRecognizer {
    let displayName = "Google 線上"
    var language = "zh_TW"

    func recognize(_ strokes: [Stroke]) async throws -> [String] {
        let w: CGFloat = 1000 * trackpadAspect
        let h: CGFloat = 1000
        let t0 = strokes.first?.first?.t ?? 0
        let ink: [[[Int]]] = strokes.map { stroke in
            [
                stroke.map { Int($0.x * w) },
                stroke.map { Int($0.y * h) },
                stroke.map { Int(($0.t - t0) * 1000) },
            ]
        }
        let body: [String: Any] = [
            "options": "enable_pre_space",
            "requests": [[
                "writing_guide": ["writing_area_width": Int(w), "writing_area_height": Int(h)],
                "ink": ink,
                "language": language,
            ]],
        ]

        var req = URLRequest(url: URL(string: "https://inputtools.google.com/request?ime=handwriting&app=mobilesearch&cs=1&oe=UTF-8")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 5

        let (data, _) = try await URLSession.shared.data(for: req)
        // 回應格式：["SUCCESS", [["id", ["候選1", "候選2", ...], ...]]]
        guard let root = try JSONSerialization.jsonObject(with: data) as? [Any],
              root.first as? String == "SUCCESS",
              let results = root.dropFirst().first as? [Any],
              let first = results.first as? [Any],
              first.count > 1,
              let candidates = first[1] as? [String] else {
            throw NSError(domain: "GoogleRecognizer", code: 1, userInfo: [NSLocalizedDescriptionKey: "辨識服務回應格式錯誤"])
        }
        return candidates
    }
}
