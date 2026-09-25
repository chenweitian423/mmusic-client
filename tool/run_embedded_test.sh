#!/usr/bin/env bash
# 跑「内置源」的引擎测试（在宿主上执行）。三件事必须写在**同一个 docker run** 里：
#   ① flutter pub get —— 每次 --rm 都是全新容器，pub 缓存是空的
#   ② 编 QuickJS 原生库 —— 它要从 pub 缓存里找 quickjs_engine 的源码
#   ③ flutter test —— 它要加载 ② 产出的 .so
#
# 拆成两次 docker run 的典型症状：满屏 "Target of URI doesn't exist"，
# 或者第 ② 步报"pub 缓存里没有 quickjs_engine 的源码"。
#
# 用法：
#   bash tool/run_embedded_test.sh                    # 只跑引擎测试
#   bash tool/run_embedded_test.sh all                # 跑全部测试
set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="${1:-test/embedded_engine_test.dart}"
echo "工程: $REPO"
echo "目标: $TARGET"
echo ""

# MSYS_NO_PATHCONV=1 是 Windows/Git Bash 必需，否则 -v 的路径会被转义掉
MSYS_NO_PATHCONV=1 docker run --rm -v "$REPO:/proj" -w /proj \
  -e TARGET="$TARGET" \
  ghcr.io/cirruslabs/flutter:3.32.0 bash -c '
set -u
echo "===== [1/3] flutter pub get ====="
flutter pub get >/dev/null 2>&1; echo "  EXIT=$?"

echo "===== [2/3] 编译 QuickJS 原生桥接（无 cmake，手写 gcc/g++）====="
bash tool/build_native.sh /tmp/mmusic-qjs 2>&1 | grep -vE "warning:" | tail -6
QJS=/tmp/mmusic-qjs/libquickjs_c_bridge_plugin.so
echo "  lib: $QJS"

echo "===== [3/3] 跑 $TARGET ====="
if [ "$TARGET" = "all" ]; then
  # 引擎测试需要原生库；其余测试不需要。全部一起跑时统一给上环境变量即可。
  LIBQUICKJSC_TEST_PATH=$QJS flutter test --no-pub 2>&1 | tr "\r" "\n" | tail -80
  echo "  TEST_EXIT=${PIPESTATUS[0]}"
else
  LIBQUICKJSC_TEST_PATH=$QJS flutter test "$TARGET" --no-pub 2>&1 | tr "\r" "\n" | tail -120
  echo "  TEST_EXIT=${PIPESTATUS[0]}"
fi

# 收尾清理：.dart_tool 指向已销毁容器的 pub 缓存，留着会让"在另一个容器里接着干活"踩坑
echo "===== 收尾清理 ====="
find /proj/.dart_tool -mindepth 1 -delete 2>/dev/null; rmdir /proj/.dart_tool 2>/dev/null
find /proj/build -mindepth 1 -delete 2>/dev/null; rmdir /proj/build 2>/dev/null
echo "  已清 .dart_tool / build（保留 /tmp/mmusic-qjs 供本容器内复用）"
'
