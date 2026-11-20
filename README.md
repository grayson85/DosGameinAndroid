# DosBox CN（华语 DOS 怀旧盒）

一款面向 **Android 手机**（后续扩展 **iPadOS 平板**）的开源经典华语 DOS 游戏模拟器，基于 **Flutter + 跨平台轻量 C++17 Libretro 宿主 + DOSBox-Pure** 构建。

## 核心特性

- **原生性能与低功耗**：`DOSBox-Pure` 开启 ARM64 动态重编译（Dynarec），通过 Flutter `Texture`（Android OpenGL ES 3.0 零拷贝）渲染，切后台自动暂停模拟线程与音频流。
- **低延迟高品质音效**：Android 端使用 Google **Oboe** 低延迟原生音频引擎，支持挂载 `.sf2` MIDI SoundFont 音源，还原《仙剑奇侠传》等经典配乐。
- **完整键鼠与多模式触控**：自研 C++ Libretro 宿主完整支持 `KEYBOARD`、`MOUSE`、`POINTER`、`JOYPAD`，提供：
  - **RPG/ACT 模式**：虚拟十字键 + Enter / Space / Alt / Esc + 自定义快捷键
  - **触控板鼠标模式**：单指滑动移动光标、轻点左键、双指轻点右键
  - **直触鼠标模式**：点哪指哪，适合《美少女梦工厂 2》等点击式游戏
  - **弹出式 PC 键盘**与外接蓝牙键鼠/手柄支持
- **直接挂载 `.zip` 与无损存档**：直接运行 `.zip` 游戏包无需解压，游戏内写入自动存至独立差分包，同时支持 **4 槽位即时存档（Save States）** 与快进。
- **内置华语 DOS 游戏目录**：解析 [`rwv/chinese-dos-games`](https://github.com/rwv/chinese-dos-games) 的 1898 款游戏元数据，支持按分类/年代筛选、搜索、SHA256 校验下载以及本地 `.zip` 导入。

## 目录结构

```text
├── .github/workflows/
│   ├── build-core-android.yml   # 自动编译 dosbox-pure arm64-v8a .so
│   └── build-android-apk.yml    # 自动测试并构建 Android Release APK
├── app/                         # Flutter 主应用 (com.gs.dosgame)
└── packages/dosbox_engine/      # 跨平台模拟器 Flutter 插件
    ├── src/                     # Android & iPadOS 共享 C++17 Libretro 宿主
    └── android/                 # Android JNI + OpenGL ES 3.0 + Google Oboe
```

## 快速构建与运行

### 方式一：GitHub Actions 自动构建（最省心）
在 GitHub 仓库的 **Actions** 页面运行 **Build Android APK** 工作流，即可自动编译 `dosbox-pure` 核心并产出可直接安装的 `app-release.apk`。

### 方式二：在本地 Mac 上真机调试
1. 确保已安装 Flutter SDK、Android Studio（含 NDK r26+）及 Xcode（可选）。
2. 编译或从 Actions 下载 `libdosbox_pure_libretro_android.so`，放置到：
   `packages/dosbox_engine/android/src/main/jniLibs/arm64-v8a/libdosbox_pure_libretro_android.so`
3. 运行应用：
   ```bash
   cd app
   flutter pub get
   flutter run
   ```

## 开源与免责声明

- 本项目仅作为开源 DOS 模拟器前端与引擎宿主，仓库内**不包含任何受版权保护的游戏文件**。
- `DOSBox-Pure` 核心遵循 GPLv2+ 协议，`libretro.h` 遵循 MIT 协议。
