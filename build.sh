#!/usr/bin/env bash
# 一键构建脚本:生成 Flutter 工程骨架 -> 注入源码 -> 打平台补丁 -> 编译 APK
# 用法:
#   bash build.sh            # 完整构建 (Android APK)
#   bash build.sh --no-apk   # 只生成工程(用于 Mac 上编 iOS)
set -e

SRC="$(cd "$(dirname "$0")" && pwd)"
WORK="$SRC/app_build"

git config --global --add safe.directory '*' 2>/dev/null || true

echo "==> [1/5] 生成 Flutter 工程骨架"
if [ ! -f "$WORK/android/app/src/main/AndroidManifest.xml" ]; then
  rm -rf "$WORK"
  flutter create --org com.sky --project-name mmusic_client --platforms android,ios "$WORK"
fi

echo "==> [2/5] 注入应用源码"
rm -rf "$WORK/lib" "$WORK/assets" "$WORK/test"
cp -r "$SRC/lib" "$WORK/lib"
mkdir -p "$WORK/assets"
cp "$SRC/assets/icon.png" "$WORK/assets/icon.png"
cp "$SRC/pubspec.yaml" "$WORK/pubspec.yaml"
mkdir -p "$WORK/tool"
cp "$SRC/tool/patch_platform.dart" "$WORK/tool/patch_platform.dart"

echo "==> [3/5] 打平台补丁(后台播放/锁屏控制/HTTP 允许)"
dart "$WORK/tool/patch_platform.dart" "$WORK"

cd "$WORK"

echo "==> [4/5] 拉取依赖"
flutter pub get

echo "==> 生成应用图标(失败不影响构建)"
dart run flutter_launcher_icons || echo "    图标生成跳过"

if [ "$1" = "--no-apk" ]; then
  echo "==> 工程已就绪: $WORK"
  echo "    Mac 上编 iOS: cd app_build && flutter build ios --release --no-codesign"
  echo "    然后用 Xcode 打开 app_build/ios/Runner.xcworkspace 签名安装"
  exit 0
fi

echo "==> [5/5] 编译 Android APK (release)"
flutter build apk --release --split-per-abi

cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk "$SRC/mmusic-arm64.apk" 2>/dev/null || true
cp build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk "$SRC/mmusic-arm32.apk" 2>/dev/null || true

echo ""
echo "=============================================="
echo "  构建完成!APK 已输出:"
echo "  mmusic-arm64.apk  (现代手机用这个)"
echo "  mmusic-arm32.apk  (老手机备用)"
echo "=============================================="
