# Blender for Android (Native ARM64 Port)

Проект нативного портирования **Blender 4.3+ / 5.x** на операционную систему Android в виде **одного самодостаточного APK**.

---

## 🎯 Архитектурные принципы

- **Без PRoot, Termux и эмуляторов**: 100% нативный процесс Android, работающий через Android NDK и Bionic libc.
- **Нативный Vulkan**: Использование официального бэкенда `GPU_backend_vulkan` из Blender напрямую через системный `libvulkan.so` (без Desktop OpenGL и тяжелых прослоек трансляции).
- **Оконная система SDL3**: Подсистема `GHOST` абстрагирована через SDL3, что обеспечивает поддержку оконного цикла `ANativeWindow`, аудио (AAudio), аппаратной клавиатуры, мыши и стилуса (S-Pen / Xiaomi Pen с чувствительностью к нажатию и наклону).
- **CPython 3.11+ NDK**: Использование апстрим-поддержки Android NDK в CPython для нативного исполнения Python-скриптов и модуля `bpy`.
- **Высокоскоростной аллокатор mimalloc**: Замена стандартных аллокаторов для максимальной скорости работы с оперативной памятью на мобильных чипсетах.

---

## 📁 Структура проекта

```text
├── .github/
│   └── workflows/
│       ├── build-deps.yml      # CI для сборки sysroot зависимостей под NDK
│       └── build-apk.yml       # CI для сборки финального Blender APK
├── scripts/
│   └── build_deps.sh           # Скрипт кросс-компиляции библиотек (oneTBB, mimalloc, Python, SDL3, FreeType)
├── cmake/
│   └── android_arm64.cmake     # CMake toolchain для Android NDK
└── android/
    └── app/
        └── src/
            └── main/
                └── AndroidManifest.xml # Манифест с настройками NativeActivity и Vulkan
```

---

## 🚀 Сборка через GitHub Actions

Сборка разделена на два независимых этапа:

### Этап 1: Сборка Sysroot зависимостей (`build-deps.yml`)
1. Перейдите во вкладку **Actions** в репозитории.
2. Выберите **Build Dependencies Sysroot (Android ARM64)**.
3. Нажмите **Run workflow**.
4. После завершения workflow артефакт `blender-deps-android-arm64.tar.gz` будет сохранен и прикреплен к релизу.

### Этап 2: Сборка Blender и генерация APK
1. Запустите workflow **Build Blender APK**.
2. Workflow автоматически скачает скомпилированный sysroot, склонирует Blender, применит Android-патчи, скомпилирует ядро и запакует итоговый `.apk`.
