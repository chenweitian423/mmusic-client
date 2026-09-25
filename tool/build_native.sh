#!/usr/bin/env bash
# 手工编译 quickjs_engine 的 Linux 原生桥接库（**只为在容器里跑引擎测试**，不参与出包）。
#
# 为什么需要它：`flutter test`（Linux 桌面）下 quickjs_engine 的 ffi.dart 走
# `_openTestLib()` 分支，要显式给一个 .so 路径；而 Android 出包那条路是
# Gradle + NDK 自动编的（见包的 android/build.gradle），跟这里无关。
#
# 为什么不放在仓库里：这是个构建产物，且只有跑引擎测试才需要。默认输出到
# /tmp/mmusic-qjs（容器内临时目录），仓库保持干净。
#
# 为什么不用包自带的 tool/build_native.sh：那个要 cmake，而 CI 用的
# cirruslabs/flutter 基础镜像里没有 cmake。原生库本身只有 5 个源文件、
# 链接一个 -lm，手写编译命令完全等价（见包内 native/CMakeLists.txt）：
#   C   : quickjs.c libregexp.c libunicode.c dtoa.c
#   C++ : libfastdev_quickjs_runtime.cpp   (需 -DCONFIG_VERSION)
#
# 用法：bash tool/build_native.sh [输出目录]
set -e

REPO="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-/tmp/mmusic-qjs}"

PUB_CACHE_DIR="${PUB_CACHE:-$HOME/.pub-cache}"
PKG_SRC="$PUB_CACHE_DIR/hosted/pub.dev"

if [ ! -d "$PKG_SRC" ]; then
  echo "错误:找不到 pub 缓存目录 $PKG_SRC —— 先跑一次 flutter pub get"
  exit 1
fi

PKG_DIR="$(find "$PKG_SRC" -maxdepth 1 -type d -name 'quickjs_engine-*' | sort -V | tail -1)"
if [ -z "$PKG_DIR" ] || [ ! -d "$PKG_DIR/native/cxx" ]; then
  echo "错误:pub 缓存里没有 quickjs_engine 的源码($PKG_DIR)"
  echo "      先跑一次 flutter pub get 再来"
  exit 1
fi

SRC="$PKG_DIR/native"
OBJ="$(mktemp -d /tmp/qjs-obj.XXXXXX)"
mkdir -p "$OUT"

echo "==> 源码:$PKG_DIR"
# ★ -D_GNU_SOURCE 是必须的：glibc 默认不暴露 localtime_r / struct tm.tm_gmtoff,
#   缺了它 quickjs.c 会报 "implicit declaration of localtime_r" 和
#   "struct tm has no member named tm_gmtoff"。CMake 构建时这个宏由 CMake 自己加上,
#   手写编译必须显式补 —— 否则只在编译到 getTimezoneOffset 时才炸,很容易误判成源码坏了。
CFLAGS="-O2 -fPIC -std=c11 -D_GNU_SOURCE -I$SRC/cxx -I$SRC/cxx/quickjs"
# 注意引号:要让 gcc 收到 -DCONFIG_VERSION="ng-0.14.0"(C 字符串字面量)
CXXFLAGS="-O2 -fPIC -std=c++17 -D_GNU_SOURCE -DCONFIG_VERSION=\"ng-0.14.0\" -I$SRC/cxx -I$SRC/cxx/quickjs"

echo "==> [1/2] 编译 QuickJS-NG(C)"
for f in quickjs libregexp libunicode dtoa; do
  gcc $CFLAGS -c "$SRC/cxx/quickjs/$f.c" -o "$OBJ/$f.o"
done

echo "==> [2/2] 编译桥接(C++)并链接"
g++ $CXXFLAGS -c "$SRC/cxx/libfastdev_quickjs_runtime.cpp" -o "$OBJ/bridge.o"
g++ -shared -o "$OUT/libquickjs_c_bridge_plugin.so" "$OBJ"/*.o -lm

find "$OBJ" -mindepth 1 -delete 2>/dev/null || true
rmdir "$OBJ" 2>/dev/null || true

echo ""
echo "==> 完成:$OUT/libquickjs_c_bridge_plugin.so"
ls -la "$OUT/libquickjs_c_bridge_plugin.so"
echo ""
echo "跑引擎测试："
echo "  LIBQUICKJSC_TEST_PATH=$OUT/libquickjs_c_bridge_plugin.so flutter test test/embedded_engine_test.dart"
