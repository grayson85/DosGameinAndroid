# DosBox CN（华语 DOS 怀旧盒）

一款面向 **Android 手机** 与 **iPad / iPhone（iPadOS / iOS）** 的开源经典华语 DOS 游戏模拟器，基于 **Flutter + 跨平台轻量 C++17 Libretro 宿主 + DOSBox-Pure** 构建。

## 核心特性

- **原生性能与低功耗**：
  - **Android**：`DOSBox-Pure` 开启 ARM64 动态重编译（Dynarec），通过 Flutter `Texture`（OpenGL ES 3.0 零拷贝）渲染，Google **Oboe** 低延迟音频。
  - **iPad / iPhone**：静态链接 `DOSBox-Pure` ARM64 核心，通过 `CVPixelBuffer` 零拷贝接入 Flutter Metal 渲染，Apple **AudioUnit** 低延迟音频，适配 iPad 4:3 大屏与外接键盘。
  - 退到后台自动暂停模拟线程与音频流，省电不发烫。
- **完整键鼠与多模式低延迟触控**：
  - **摇杆/键盘（RPG/ACT 默认）**：按压动态定位虚拟摇杆 + 方向防抖扇区 + Enter / Space / Alt / Esc。
  - **十字键/键盘**：传统 8 向滑动十字键。
  - **触控板鼠标**：单指滑动相对移动光标、轻点左键、双指轻点右键，底部配备独立左/右键。
  - **直触鼠标**：点击屏幕任意位置直接左键点击，右下角配独立左/右键。
  - **PC 虚拟键盘**与物理蓝牙键盘支持。
- **直接挂载 `.zip`、虚拟光驱与即时存档**：
  - 支持直接运行 `.zip` 无需解压，差分存档自动保存。
  - 详情页内置 **「光驱模式启动（#D）」**，解决《三国志 5》《三国志 5 威力加强版》等经典光荣游戏的光盘检测问题。
  - 支持 **4 槽位即时存档（Save States）**、**1x/2x/4x 快进** 与 `.sf2` MIDI SoundFont 音源导入。
- **内置华语 DOS 游戏目录**：解析 [`rwv/chinese-dos-games`](https://github.com/rwv/chinese-dos-games) 的 1898 款经典游戏元数据，支持按类型筛选、中英文搜索、SHA256 校验下载以及本地 `.zip` 导入。

---

## 目录结构

```text
├── .github/workflows/
│   ├── build-core-android.yml   # 自动编译 dosbox-pure Android arm64-v8a .so
│   ├── build-android-apk.yml    # 自动测试并构建 Android Release APK
│   └── build-ios-ipa.yml        # 自动编译 dosbox-pure iOS arm64 静态库并打包 .ipa
├── app/                         # Flutter 主应用 (com.gs.dosgame)
└── packages/dosbox_engine/      # 跨平台模拟器 Flutter 插件
    ├── src/                     # Android & iOS 共享 C++17 Libretro 宿主
    ├── android/                 # Android JNI + OpenGL ES 3.0 + Google Oboe
    └── ios/                     # iOS/iPadOS CVPixelBuffer(Metal) + AudioUnit
```

---

## 安装与使用指南

### Android 手机安装（最简单）
1. 打开本仓库的 **GitHub Actions** → 点击最新的 **Build Android APK** 成功记录。
2. 在页面底部 **Artifacts** 下载 **`dosbox-cn-android-arm64-apk`**。
3. 解压得到 `app-release.apk`，传到 Android 手机直接安装即可。

---

### iPad / iPhone 免费签名安装（SideStore 保姆级教程，无需 \$99 开发者账号）

> 由于苹果限制，没有 \$99/年开发者账号时，GitHub Actions 会产出**未签名的 `DosBoxCN-unsigned.ipa`**。使用开源工具 **SideStore** 可以用你的**普通免费 Apple ID** 直接签名安装，并且**之后在 iPad 上连 Wi-Fi 即可自己续签，无需再插 Mac**！

#### 第一步：下载未签名 IPA
1. 打开本仓库的 **GitHub Actions** → 点击最新的 **Build iOS / iPadOS IPA** 成功记录。
2. 在页面底部 **Artifacts** 下载 **`dosbox-cn-ios-ipa`**，解压得到 **`DosBoxCN-unsigned.ipa`**（可以直接用 Safari 在 iPad 上下载到「文件」App 里）。

#### 第二步：首次在 iPad 上安装 SideStore（仅首次需要 Mac，约 5 分钟）
1. 在 Mac 上前往 [SideStore 官网](https://sidestore.io/) 下载并安装 **AltServer**（或官方推荐的 **SideServer / iloader**）。
2. 用数据线将 iPad 连接到 Mac，在 iPad 上点击「信任此电脑」。
3. 打开 iPad **设置 → 隐私与安全性 → 开发者模式** 并开启（按提示重启一次 iPad）。
4. 在 Mac 上点击顶部菜单栏 AltServer 图标 → **按住 Option (⌥) 键** → 点击 **Sideload .ipa** → 选择你的 iPad → 选中从 SideStore 官网下载的 `SideStore.ipa`，输入你的免费 Apple ID 完成安装。
5. 使用 Mac 工具（**JitterbugPair**，SideStore 官网提供下载）生成当前 iPad 的配对文件（`.mobiledevicepairing`），通过隔空投送（AirDrop）发送到 iPad 的「文件」App。
6. 在 iPad App Store 免费下载 **StosVPN**（或 **WireGuard**，按 SideStore 官网指引导入本地回环配置）并开启——这一步是为了让 SideStore 在不插电脑的情况下本地完成签名续签。
7. 在 iPad 上进入 **设置 → 通用 → VPN 与设备管理**，信任你的 Apple ID 开发者证书，然后打开 **SideStore**，导入刚才的配对文件并登录同一个 Apple ID。

#### 第三步：用 SideStore 安装 DosBox CN
1. 确保 iPad 已开启 **StosVPN / WireGuard** 并连着 Wi-Fi。
2. 打开 **SideStore** → 切换到 **My Apps** → 点击左上角 **`+`** 号 → 选择第一步下载好的 **`DosBoxCN-unsigned.ipa`**。
3. 等待约 10~20 秒自动签名安装完成，桌面就会出现 **DosBox CN** 图标，直接打开即可在 iPad 4:3 大屏上畅玩《仙剑奇侠传》《三国志 5》！

#### 第四步：7 天到期免插电脑自动续签（推荐配置）
- **手动续签**：每 7 天内，在 iPad 连 Wi-Fi 时打开 StosVPN，再打开 SideStore 点一下 **Refresh All**（3 秒完成）。
- **全自动续签**：打开 iPad 自带的 **快捷指令（Shortcuts）** → **自动化** → 新建个人自动化（例如每天凌晨 3:00 或每天充电时）→ 添加操作：
  1. 开启 StosVPN / WireGuard
  2. 运行 SideStore 的 **Refresh All Apps**
  - 设为「立即运行」，从此再也不用手动管 7 天过期！

---

### 开发者本地运行（Mac + Xcode / Android Studio）

#### Android 本地调试
1. 从 Actions 下载（或用 NDK 编译）`libdosbox_pure_libretro_android.so`，放到：
   `packages/dosbox_engine/android/src/main/jniLibs/arm64-v8a/libdosbox_pure_libretro_android.so`
2. 运行：
   ```bash
   cd app && flutter pub get && flutter run
   ```

#### iPad / iPhone 本地用 Xcode 直接运行
1. 在 Mac 上编译 `libdosbox_pure_ios.a`（参考 `.github/workflows/build-ios-ipa.yml`），放到 `packages/dosbox_engine/ios/Libs/libdosbox_pure_ios.a`。
2. 在 `app/` 目录生成 iOS 工程并运行：
   ```bash
   cd app
   flutter create --platforms=ios --org com.gs --project-name dosbox_cn .
   flutter pub get
   open ios/Runner.xcworkspace
   ```
3. 在 Xcode 中选中 `Runner` → **Signing & Capabilities** → 选择你的免费 Apple ID（Personal Team），连接 iPad 点击 ▶ 即可运行。

---

## 开源与免责声明

- 本项目仅作为开源 DOS 模拟器前端与引擎宿主，仓库内**不包含任何受版权保护的游戏文件**。
- `DOSBox-Pure` 核心遵循 GPLv2+ 协议，`libretro.h` 遵循 MIT 协议。
