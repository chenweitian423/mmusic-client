# M音乐 —— mmusic 手机客户端(Flutter,iOS + Android)

网易云风格的手机客户端,连接你自建的 mmusic(MusicFree API)服务。

功能:服务器地址可配置 / 账号登录 / 多音源搜索(zypt 五源 + MusicFree 插件)/
推荐歌单 / 五平台排行榜 / 我喜欢的音乐(与网页端同步)/ 收藏歌单 /
完整播放器(旋转封面、同步歌词、音质选择、列表循环·单曲·随机)/
后台播放 + 通知栏/锁屏控制(Android MediaSession、iOS 控制中心)。

## 目录结构

```
mmusic-client/
├── lib/                  # 全部应用源码(Dart)
├── assets/icon.png       # 应用图标
├── pubspec.yaml          # 依赖配置
├── tool/patch_platform.dart  # 平台补丁(后台播放/HTTP 权限等,构建时自动执行)
├── build.sh              # 一键构建脚本(核心)
├── build-apk-docker.bat  # Windows 上双击即可用 Docker 编 APK
└── .github/workflows/    # GitHub Actions 云端编译(可选)
```

`build.sh` 会自动:`flutter create` 生成工程骨架 → 注入 `lib/` 源码 →
打平台补丁 → `flutter build apk`。**不要手动改 app_build 里的文件**,
重新运行脚本会覆盖。

## 一、编译 Android APK(三选一)

### 方式 A:Windows + Docker(推荐,一条命令)

前提:装有 Docker Desktop(或任何能跑 docker 的机器)。

双击 `build-apk-docker.bat`,或手动执行:

```
docker run --rm -v "本文件夹路径":/proj -w /proj ghcr.io/cirruslabs/flutter:3.32.0 bash /proj/build.sh
```

首次运行会下载约 3GB 镜像;编译完成后,本文件夹里会出现:

- `mmusic-arm64.apk` —— 传到手机安装(近几年的手机都用这个)
- `mmusic-arm32.apk` —— 老旧手机备用

> 若提示镜像标签不存在,把 `3.32.0` 换成 `stable`。
> 若在 NAS 等 Linux 机器上跑,把路径换成对应目录即可。

### 方式 B:Mac(你反正要编 iOS,可顺手编 APK)

Mac 上装好 Flutter 和 Android Studio(含 Android SDK)后:

```
bash build.sh
```

### 方式 C:GitHub Actions(云端白嫖编译)

把本文件夹推到 GitHub 仓库,Actions 会自动编译,
在仓库 Actions 页面下载 `mmusic-apk` 产物即可。
(public 仓库 Actions 免费不限量;代码里不含任何私有服务器地址,可放心公开)

## 二、编译 iOS(Mac + 自签证书)

1. Mac 上安装 Flutter(https://docs.flutter.dev/get-started/install/macos)
   和 Xcode,然后在本文件夹执行:

   ```
   bash build.sh --no-apk        # 只生成工程,不编 APK
   cd app_build
   flutter build ios --release --no-codesign
   open ios/Runner.xcworkspace
   ```

2. Xcode 中:选中 Runner → Signing & Capabilities →
   Team 选你的开发者账号(个人免费账号即可),
   Bundle Identifier 已设为 `com.sky.mmusicClient`,如有冲突随意改一个。

3. iPhone 连上 Mac,顶部设备选你的手机,⌘R 运行安装。
   手机上到「设置 → 通用 → VPN与设备管理」信任你的证书。

> 免费个人证书签的 App 有效期 7 天,过期重新 ⌘R 一次即可;
> 付费开发者账号(¥688/年)有效期 1 年。
> 后台播放权限(UIBackgroundModes=audio)已由补丁脚本自动写入,无需手动配置。

### 不想用 Mac?Windows 侧载路线(曲线方案)

iOS 无法在 Windows 上编译(苹果限制),但可以:

1. 把本文件夹推到 GitHub 私有仓库,Actions 里手动运行
   **Build iOS (unsigned ipa)** 工作流(用的是 GitHub 免费 macOS 云机器);
2. 下载产物 `mmusic-unsigned.ipa`;
3. Windows 上安装 [Sideloadly](https://sideloadly.io/),iPhone 用数据线连电脑,
   拖入 ipa,登录你的 Apple ID → 自动签名并安装。
4. 手机上「设置 → 通用 → VPN与设备管理」信任证书。

和免费证书一样 7 天有效,过期用 Sideloadly 重装一次即可。
有 Mac 的话仍推荐 Xcode 路线,更省事。

## 三、使用

1. 打开 App → 输入你的 mmusic 服务器地址(如 `http://192.168.x.x:8033`)
2. 用网页端的账号密码登录(注册请在网页端完成)
3. 外网访问:若服务器有公网映射/内网穿透,把服务器地址换成对应外网地址即可。

## 常见问题

- **某首歌播放失败**:上游音源没有该曲目版权或链接失效,App 会自动尝试
  多档音质并跳到下一首;换个音源(如「元力KW」)搜索通常能播。
- **网易云(wy)源歌曲偶尔取不到直链**:实测服务端 zypt/wy 直链接口偶发 404,
  App 已做多音质回退;推荐优先用插件源(元力KW/元力WY)。
- **iOS 上封面/音频加载失败**:确认走的是 HTTP,补丁已放开 ATS
  (NSAllowsArbitraryLoads),若你自己改过 Info.plist 请保留该项。
- **修改代码后重新构建**:直接改 `lib/` 下源码,重跑构建脚本即可。
