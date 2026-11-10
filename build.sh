#!/bin/zsh
# 編譯並打包成 觸控板手寫.app（放在 build/ 底下）
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/觸控板手寫.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/TrackpadHandwriting "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"

# 有開發者憑證就用憑證簽（輔助使用權限重編譯後不會失效）；沒有就用 ad-hoc 簽名
IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development|Developer ID/ {print $2; exit}')
codesign --force --sign "${IDENTITY:--}" "$APP"

echo "完成：$APP"
