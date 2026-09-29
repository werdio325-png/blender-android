# Blender for Android (Native ARM64 Port) 🚀

[![Build Blender 5.2 Android APK](https://github.com/werdio325-png/blender-android/actions/workflows/build-apk.yml/badge.svg)](https://github.com/werdio325-png/blender-android/actions/workflows/build-apk.yml)
[![GitHub Release](https://img.shields.io/github/v/release/werdio325-png/blender-android?include_prereleases&color=orange)](https://github.com/werdio325-png/blender-android/releases)
[![Platform](https://img.shields.io/badge/Platform-Android%2010%2B%20(API%2029%2B)-green.svg)](https://developer.android.com)
[![Arch](https://img.shields.io/badge/Architecture-ARM64--v8a-blue.svg)](https://developer.arm.com)
[![Graphics](https://img.shields.io/badge/Graphics-Vulkan%20Native-red.svg)](https://www.vulkan.org)

> [!WARNING]
> **EXPERIMENTAL PROJECT / RESEARCH PROTOTYPE**  
> This is an active work-in-progress research project bringing **Blender 5.x** natively to Android ARM64 devices without emulation or Linux chroots. Stability, performance, and touch/stylus UX are actively being developed.

---

## 📥 Downloads

Grab the latest standalone APK directly from GitHub Releases:
👉 **[Download Latest Blender Android APK](https://github.com/werdio325-png/blender-android/releases/latest)**

---

## 🎯 Architectural Principles

- **100% Native Execution (No PRoot, Termux, or Box64)**: Runs as a native Android application using Android NDK toolchain and Bionic libc.
- **Hardware-Accelerated Vulkan**: Driven directly through Blender's native `GPU_backend_vulkan` and system `libvulkan.so` (no translation layers).
- **Modern Windowing & Input via SDL3**: `GHOST` subsystem adapted to SDL3 for `ANativeWindow` lifecycle, hardware keyboard, mouse, AAudio, and stylus support with pressure sensitivity.
- **Embedded CPython 3.13**: Built specifically for Android Bionic for full `bpy` scripting and addon compatibility.
- **Optimized Memory Allocation**: Powered by `mimalloc` / `oneTBB` optimized for mobile ARM64 memory architectures.
- **Self-Contained Single APK**: All dependencies, shared objects, datafiles, and python runtime packages bundled in a single installable `.apk`.

---

## 📊 Current Status & Roadmap

| Feature | Status | Notes |
| :--- | :--- | :--- |
| **NDK Cross-Compilation** | 🟢 Complete | All 7,100+ compilation units build cleanly |
| **Shared Libraries & Packaging** | 🟢 Complete | Stripped, signed single APK (150-170 MB) |
| **NativeActivity Lifecycle** | 🟢 Complete | Window creation, lifecycle sync & logcat piping |
| **Logcat Diagnostics** | 🟢 Complete | Output redirected to `adb logcat -s BlenderCore:*` |
| **Display Backend (SDL3 / GHOST)** | 🟡 In Progress | SDL3 window attachment & video driver integration |
| **UI Interaction & Gestures** | ⚪ Planned | Multi-touch, pinch-to-zoom, virtual controls |
| **Eevee Next & Cycles Support** | ⚪ Planned | Mobile GPU compute shaders & Vulkan optimization |

---

## 🛠️ Testing & Debugging via ADB

1. **Install the APK**:
   ```bash
   adb install -r -d Blender-Android-arm64.apk
   ```

2. **Launch Blender**:
   ```bash
   adb shell am start -n org.blender.app/android.app.NativeActivity
   ```

3. **Stream Runtime Logs**:
   ```bash
   adb logcat -s BlenderNative:* BlenderCore:* AndroidRuntime:* DEBUG:*
   ```

---

## 📁 Repository Structure

```text
├── .github/
│   └── workflows/
│       └── build-apk.yml       # Automated CI/CD building APK on GitHub Actions
├── scripts/
│   ├── build_blender.sh        # Core build script, patches, and APK assembly
│   └── build_deps.sh           # Sysroot builder for third-party C/C++ dependencies
├── android/
│   └── app/src/main/
│       └── AndroidManifest.xml # NativeActivity, Vulkan requirements & permissions
└── cmake/                      # Toolchain definitions and dependency helpers
```

---

## 🤝 Contributing

Contributions, bug reports, and hardware compatibility reports are very welcome!  
Feel free to open an **Issue** or submit a **Pull Request**.

---

<details>
<summary><b>🇷🇺 Описание проекта на русском языке (Нажмите, чтобы развернуть)</b></summary>

### Blender для Android (Нативный порт ARM64)

Экспериментальный проект по нативному портированию актуальной кодовой базы **Blender 5.x** на Android в виде **одного автономного APK**.

#### Ключевые особенности:
- **Никаких эмуляторов и Termux**: Прямой запуск через Android NDK и Bionic libc.
- **Чистый нативный Vulkan**: Официальный Vulkan-бэкенд Blender, работающий напрямую с драйвером GPU Android.
- **Оконная подсистема SDL3**: Управление окнами `ANativeWindow`, клавиатура, мышь, стилус.
- **Встроенный CPython 3.13**: Выполнение Python-скриптов и аддонов Blender (`bpy`).
- **Компактный размер**: Стриппинг библиотек и упаковка всех необходимых данных в один `.apk`.

</details>
