import Foundation
import CMultitouch

/// 一根手指在某一瞬間的狀態（已轉成 Swift 型別）。
struct TouchSample {
    let id: Int32
    let x: CGFloat      // 0~1，左→右
    let y: CGFloat      // 0~1，下→上
    let size: CGFloat
    let touching: Bool
}

/// 接收觸控板原始觸控（絕對座標），並在主執行緒轉發。
final class MultitouchManager {
    static let shared = MultitouchManager()

    /// 每個觸控 frame 呼叫一次（主執行緒）。
    var onFrame: (([TouchSample], TimeInterval) -> Void)?

    private(set) var deviceCount: Int32 = 0

    func start() {
        let result = mt_start { ptr, count, timestamp in
            guard let ptr else {
                MultitouchManager.shared.deliver([], timestamp)
                return
            }
            var samples: [TouchSample] = []
            samples.reserveCapacity(Int(count))
            for i in 0..<Int(count) {
                let t = ptr[i]
                samples.append(TouchSample(
                    id: t.identifier,
                    x: CGFloat(t.x),
                    y: CGFloat(t.y),
                    size: CGFloat(t.size),
                    touching: t.state == 4 || t.state == 5
                ))
            }
            MultitouchManager.shared.deliver(samples, timestamp)
        }
        deviceCount = result
        if result < 0 {
            NSLog("[Handwriting] 無法載入 MultitouchSupport 私有框架")
        } else {
            NSLog("[Handwriting] 已連接 \(result) 個觸控裝置")
        }
    }

    func stop() { mt_stop() }

    private func deliver(_ samples: [TouchSample], _ timestamp: Double) {
        DispatchQueue.main.async { [weak self] in
            self?.onFrame?(samples, timestamp)
        }
    }
}
