import AppKit
import SwiftUI

// MARK: - 浮動視窗（不搶焦點，游標仍留在原本的 App）

final class HandwritingPanel: NSPanel {
    private var hostingController: NSHostingController<HandwritingView>?

    init(model: HandwritingModel) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 380),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false        // 陰影由 SwiftUI 的玻璃材質處理
        ignoresMouseEvents = true // 不接收滑鼠，寫字完全靠觸控板原始資料
        hidesOnDeactivate = false
        animationBehavior = .none

        let host = NSHostingController(rootView: HandwritingView(model: model))
        host.sizingOptions = []
        let size = host.sizeThatFits(in: NSSize(width: 2000, height: 2000))
        host.view.frame = NSRect(origin: .zero, size: size)
        contentView = host.view
        hostingController = host
        setContentSize(size)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - 主畫面

struct HandwritingView: View {
    @ObservedObject var model: HandwritingModel
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 12) {
            CandidateBar(model: model)
            InkCanvas(model: model)
                .frame(width: 428, height: 428 / trackpadAspect)
            footer
        }
        .padding(16)
        .frame(width: 460)
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
        .padding(24) // 讓玻璃邊緣的光暈不被視窗裁掉
        .scaleEffect(appeared ? 1 : 0.92)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) { appeared = true }
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            hint("return", "送出")
            hint("1–9", "選字")
            hint("delete", "刪筆畫")
            hint("esc", "關閉")
            Spacer(minLength: 0)
            Text(model.engineName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 4)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            Text(label)
                .font(.system(size: 11))
        }
        .foregroundStyle(.secondary)
    }
}

// MARK: - 候選字列

struct CandidateBar: View {
    @ObservedObject var model: HandwritingModel

    var body: some View {
        HStack(spacing: 6) {
            if model.displayedCandidates.isEmpty {
                HStack(spacing: 8) {
                    if model.isRecognizing {
                        ProgressView().controlSize(.small)
                        Text("辨識中…")
                    } else if let msg = model.statusMessage {
                        Image(systemName: "exclamationmark.triangle")
                        Text(msg)
                    } else {
                        Image(systemName: "hand.point.up.left")
                        Text("用一根手指在觸控板上書寫")
                    }
                }
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
            } else {
                GlassEffectContainer(spacing: 6) {
                    HStack(spacing: 6) {
                        ForEach(Array(model.displayedCandidates.prefix(7).enumerated()), id: \.offset) { index, text in
                            CandidateChip(
                                index: index + 1,
                                text: text,
                                primary: index == 0 && !model.showingAlternates
                            )
                        }
                    }
                }
                Spacer(minLength: 0)
                if model.showingAlternates {
                    Text("按數字替換")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(height: 40)
        .animation(.easeOut(duration: 0.18), value: model.displayedCandidates)
    }
}

struct CandidateChip: View {
    let index: Int
    let text: String
    let primary: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(index)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(primary ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.tertiary))
            Text(text)
                .font(.system(size: 20, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(primary ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        // 面板永遠不是 key window（才不會搶走輸入焦點），系統會把玻璃顯示成「非作用中」的去色樣式，
        // 所以第一候選額外鋪一層藍色，確保看得出是預設選項
        .background(Capsule().fill(Color.blue.opacity(primary ? 0.75 : 0)))
        .glassEffect(primary ? .regular.tint(.blue) : .regular, in: .capsule)
    }
}

// MARK: - 墨跡畫布（同步顯示觸控板上的手寫）

struct InkCanvas: View {
    @ObservedObject var model: HandwritingModel

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(.black.opacity(0.06))
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(.white.opacity(0.25), lineWidth: 0.5)

                // 中央十字輔助線（類似田字格）
                Path { p in
                    p.move(to: CGPoint(x: size.width / 2, y: 14))
                    p.addLine(to: CGPoint(x: size.width / 2, y: size.height - 14))
                    p.move(to: CGPoint(x: 14, y: size.height / 2))
                    p.addLine(to: CGPoint(x: size.width - 14, y: size.height / 2))
                }
                .stroke(.secondary.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 5]))

                Canvas { ctx, canvasSize in
                    let all = model.strokes + (model.currentStroke.isEmpty ? [] : [model.currentStroke])
                    for stroke in all {
                        ctx.stroke(
                            Self.path(for: stroke, in: canvasSize),
                            with: .color(.primary),
                            style: StrokeStyle(lineWidth: 5.5, lineCap: .round, lineJoin: .round)
                        )
                    }
                }

                if let p = model.fingerPosition {
                    Circle()
                        .fill(Color.blue.opacity(0.4))
                        .frame(width: 22, height: 22)
                        .blur(radius: 3)
                        .position(x: p.x * size.width, y: p.y * size.height)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    /// 用中點二次曲線讓筆畫平滑
    static func path(for stroke: Stroke, in size: CGSize) -> Path {
        var path = Path()
        let pts = stroke.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        guard let first = pts.first else { return path }
        path.move(to: first)
        if pts.count == 1 {
            path.addLine(to: CGPoint(x: first.x + 0.1, y: first.y + 0.1)) // 點
            return path
        }
        for i in 1..<pts.count {
            let mid = CGPoint(x: (pts[i - 1].x + pts[i].x) / 2, y: (pts[i - 1].y + pts[i].y) / 2)
            path.addQuadCurve(to: mid, control: pts[i - 1])
        }
        path.addLine(to: pts[pts.count - 1])
        return path
    }
}
