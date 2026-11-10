# 觸控板手寫

在 MacBook 觸控板上用手指寫字，辨識後直接輸入到目前的文字欄位。手寫板使用 macOS 原生的 Liquid Glass（`.glassEffect`）。

需要 macOS 26 以上（Apple Silicon）。

## 下載安裝

1. 到 [Releases](../../releases/latest) 下載 `TrackpadHandwriting.zip`，解壓縮後把「觸控板手寫.app」拖到「應用程式」資料夾。
2. 這個 App 沒有經過 Apple 公證，第一次打開會被擋。在終端機執行下面這行解除隔離，再打開 App：
   ```bash
   xattr -dr com.apple.quarantine "/Applications/觸控板手寫.app"
   ```
3. 開啟權限：打開「系統設定」，在搜尋欄輸入 `輔助使用`，進入「允許輔助應用程式控制電腦」，把「觸控板手寫」打開（清單裡沒有就按「＋」加入）。約 2 秒內自動生效，選單列會出現 ✏️ 圖示。

## 從原始碼編譯

```bash
./build.sh
open "build/觸控板手寫.app"
```

> 目前用 ad-hoc 簽名，**每次重新編譯後**系統會把它當成新 App，需要到輔助使用清單把舊的移除、重新勾選。

## 使用方式

| 動作 | 效果 |
|---|---|
| 連按觸控板三下 | 開啟／關閉手寫板 |
| 一根手指在觸控板上寫 | 寫字（整塊觸控板對應整個畫布） |
| 停筆約 0.5 秒 | 顯示候選字 |
| 停筆約 1.3 秒 | 自動送出第一候選 |
| `1`–`9` | 選擇候選字；送出後按數字可替換剛送出的字 |
| `space` | 立即送出 |
| `delete` | 刪除上一筆畫（畫布空了就刪除 App 裡的前一個字） |
| 雙指輕點 | 刪除上一筆畫 |
| `return` | 送出並關閉 |
| `esc` | 不送出直接關閉 |
| 其他按鍵 | 送出並關閉，按鍵照常輸入 |

## 辨識引擎（選單列切換）

- **Apple 手寫引擎**（預設，推薦）：macOS 內建的 `CoreHandwriting`，跟 iPad Scribble、備忘錄手寫是同一套。完全離線、直接看筆畫，每個字約 1–15 ms。
- **Apple Vision**：把筆畫畫成圖片再做文字辨識，準確度差很多，只當備援。系統找不到手寫引擎時會自動改用它。
- **Google 線上**：會把筆畫座標傳到 Google（inputtools.google.com，非官方介面），切換時會再確認一次。

自我測試結果（7 個模擬手寫字，第一候選正確數）：

| 引擎 | 工整 | 抖動 ×3 | 抖動 ×5 |
|---|---|---|---|
| Apple 手寫引擎 | 7/7 | 7/7 | 7/7 |
| Apple Vision | 4/7 | 2/7 | 1/7 |

（也試過開源的 Zinnia + Tegaki 繁中模型，只有 1/7：那個模型的繁中字大多只有一個借自簡中／日文的訓練樣本，已移除。）

## 運作原理

- `MultitouchSupport.framework`（私有框架）讀取觸控板手指的絕對座標 → 畫在畫布上
- `CGEventTap`：偵測 clickCount == 3 開啟手寫板；寫字時吞掉點擊／捲動，避免誤觸背景 App；攔截快捷鍵
- 手寫板是 non-activating panel，不會搶走原本 App 的輸入焦點
- 送字：剪貼簿 + ⌘V（之後還原原本剪貼簿），開著注音也能正常輸入

## 已知限制

- 系統的「連按三下選取整行」會被這個功能取代（可在選單關閉觸發）。
- 前兩下點擊會讓 App 先選取一個詞；程式會用輔助使用 API 還原游標位置，但 Chrome／Electron 類 App 不一定支援。
- 三指手勢（切換桌面等）仍由系統處理，寫字請用一根手指。
- 觸控板（MultitouchSupport）和手寫引擎（CoreHandwriting）都是私有框架，未來的 macOS 版本可能改變。手寫引擎失效時會自動退回 Vision。

## 自我測試

```bash
# 開啟手寫板並放入模擬手寫的「中」（檢查外觀）
./build/觸控板手寫.app/Contents/MacOS/TrackpadHandwriting --demo

# 辨識 7 個模擬手寫字並印出準確率（--engine 可選 apple / vision / google；DEMO_JITTER=5 讓筆畫更潦草）
./build/觸控板手寫.app/Contents/MacOS/TrackpadHandwriting --test --engine apple
```

都不需要權限。
