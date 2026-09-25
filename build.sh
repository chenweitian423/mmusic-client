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
# ★ 整个 assets/ 都要拷（内置源需要 assets/js 宿主环境 + assets/gen 依赖产物
#   + assets/plugins 随包插件）。早期这里只拷了 icon.png,内置源一上来就缺资源。
cp -r "$SRC/assets" "$WORK/assets"
cp "$SRC/pubspec.yaml" "$WORK/pubspec.yaml"
mkdir -p "$WORK/tool"
cp "$SRC/tool/patch_platform.dart" "$WORK/tool/patch_platform.dart"

# 随包插件是可选的（.js 被 .gitignore 忽略）：有就带上，没有就打出个空插件包，
# 用户在 App 里导入即可。这里如实报个数，免得事后怀疑"是不是没打进去"。
BUILTIN_PLUGINS="$(find "$SRC/assets/plugins" -name '*.js' 2>/dev/null | wc -l | tr -d ' ')"
echo "    随包插件:$BUILTIN_PLUGINS 个$( [ "$BUILTIN_PLUGINS" = "0" ] && echo '（不含插件，App 内可导入）')"

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
