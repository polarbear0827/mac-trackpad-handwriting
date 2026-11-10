#ifndef CMULTITOUCH_H
#define CMULTITOUCH_H

/// 觸控板上單一手指的簡化資料。座標為 0~1 的正規化值，原點在觸控板左下角。
typedef struct {
    int identifier;   // 手指追蹤 ID（同一根手指在離開前不變）
    int state;        // 4 = 剛接觸, 5 = 接觸中, 其他 = 懸停/離開
    float x;
    float y;
    float size;       // 接觸面積（可當壓力參考）
} MTTouchPoint;

/// 每一個 frame 都會呼叫（在背景執行緒）。
typedef void (*MTFrameCallback)(const MTTouchPoint *touches, int count, double timestamp);

/// 載入私有框架 MultitouchSupport 並開始接收所有觸控裝置的原始觸控。
/// 回傳成功啟動的裝置數量，失敗回傳 -1。
int mt_start(MTFrameCallback callback);

/// 停止接收。
void mt_stop(void);

#endif
