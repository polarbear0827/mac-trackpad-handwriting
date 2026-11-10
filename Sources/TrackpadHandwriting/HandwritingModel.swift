import Foundation
import Combine

/// 一個筆畫點：座標為 0~1 的正規化值（左上原點），t 為秒。
struct StrokePoint {
    var x: CGFloat
    var y: CGFloat
    var t: TimeInterval
}

typealias Stroke = [StrokePoint]

/// 觸控板的寬高比（MacBook 內建觸控板約 1.6:1），畫布照這個比例顯示。
let trackpadAspect: CGFloat = 1.6

final class HandwritingModel: ObservableObject {
    @Published var strokes: [Stroke] = []
    @Published var currentStroke: Stroke = []
    /// 手指目前位置（正在接觸時才有值），用來顯示發光游標點
    @Published var fingerPosition: CGPoint?

    /// 尚未送出的辨識結果
    @Published var candidates: [String] = []
    /// 剛送出的字，以及可以用數字鍵替換的其他候選
    @Published var lastCommitted: String?
    @Published var alternates: [String] = []

    @Published var isRecognizing = false
    @Published var engineName = ""
    @Published var statusMessage: String?

    var hasInk: Bool { !strokes.isEmpty || !currentStroke.isEmpty }

    /// 目前畫面上方要顯示的候選列（待送出優先，否則顯示剛送出的替換選項）
    var displayedCandidates: [String] { candidates.isEmpty ? alternates : candidates }
    var showingAlternates: Bool { candidates.isEmpty && !alternates.isEmpty }

    func reset() {
        strokes = []
        currentStroke = []
        fingerPosition = nil
        candidates = []
        lastCommitted = nil
        alternates = []
        isRecognizing = false
        statusMessage = nil
    }
}
