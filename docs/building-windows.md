# Сборка под Windows

Flutter не умеет кросс-компилировать Windows-приложения с Linux — сборка
делается **на самой Windows-машине**. Ничего не проверялось вживую на
Windows в среде, где писался этот код (нет доступной Windows-машины) —
см. [`docs/roadmap.md`](roadmap.md). Инструкция ниже собрана по
официальным требованиям Flutter/`media_kit`/`sqflite_common_ffi`, а не
проверена запуском.

## 1. Предварительные требования

1. **Flutter SDK** (stable-канал), тот же или более новый, чем указан в
   `pubspec.yaml` (`environment: sdk: ^3.13.0`). Установка:
   ```powershell
   git clone https://github.com/flutter/flutter.git -b stable C:\src\flutter
   setx PATH "%PATH%;C:\src\flutter\bin"
   ```
   Откройте новый терминал после `setx`, чтобы PATH подхватился.

2. **Visual Studio 2022** (Community — бесплатно) с компонентом
   **"Desktop development with C++"**. Это даёт MSVC-тулчейн и Windows
   SDK, без которых `flutter build windows` не соберёт нативный runner.
   Поставить можно через [Visual Studio Installer](https://visualstudio.microsoft.com/downloads/) —
   при установке отметьте именно workload "Desktop development with C++",
   отдельный VS Code сюда не подходит.

3. **Git for Windows** (для `flutter pub get`, часть пакетов тянется из
   git-репозиториев напрямую).

4. Включить поддержку Windows-приложений в Flutter (обычно уже
   включено по умолчанию в актуальных версиях, но на всякий случай):
   ```powershell
   flutter config --enable-windows-desktop
   ```

5. Проверить окружение:
   ```powershell
   flutter doctor -v
   ```
   Должны быть зелёные галочки у "Flutter" и "Visual Studio". Если
   Visual Studio показывает предупреждение — почти всегда не хватает
   именно workload "Desktop development with C++", а не самой VS.

## 2. Сборка

```powershell
cd путь\до\AudiLoc
flutter pub get

# Отладочный запуск (если есть Windows-машина под рукой)
flutter run -d windows

# Релизная сборка
flutter build windows
```

Готовое приложение окажется в:
```
build\windows\x64\runner\Release\audiloc.exe
```
вместе со всеми нужными `.dll` рядом (Flutter сам копирует туда
engine-библиотеки при сборке).

## 3. Нативные зависимости — что собирается автоматически

Дополнительно ничего руками ставить не нужно — все нативные библиотеки
подключаются через `flutter build windows` из соответствующих пакетов:

- **`media_kit_libs_windows_audio`** — бандлит нужные библиотеки
  (на основе libmpv) прямо в сборку через свой `CMakeLists.txt`,
  подключённый в `windows/flutter/generated_plugins.cmake`. Отдельно
  ставить mpv/VLC не требуется.
- **`sqflite_common_ffi`** — на Windows использует собственный бандл
  `sqlite3.dll`, устанавливать SQLite отдельно не нужно.
- **`audiotags`** (чтение/запись тегов, [ADR 0002](adr/0002-audiotags-instead-of-id3.md))
  — нативный код на Rust, встроенный через `cargokit`. Первая сборка
  на новой машине **скачает и закэширует Rust-тулчейн автоматически**
  (нужен интернет на этот момент) и скомпилирует crate под Windows —
  из-за этого первый `flutter build windows` заметно дольше
  последующих. Отдельно устанавливать Rust/`rustup` не требуется.
## 4. Передача файлов

Передача аудиофайлов между устройствами встроена в само приложение —
HTTP-сервер/клиент AudiLoc на `dart:io`/`dio`
([ADR 0010](adr/0010-built-in-file-transfer.md)). Ничего стороннего
ставить не нужно.

## 5. Известные ограничения

- Не проверялось запуском на реальной Windows-машине — возможны
  нюансы, которые всплывают только при живом запуске (см. п.
  "Windows-сборки" в [`docs/roadmap.md`](roadmap.md)).
- Есть проблема с файлом windows.tar.gz сборщик не может его
  распаковать. Необходимо в ручную распаковать архив перед сборкой.
- Брандмауэр Windows при первом запуске обычно спрашивает разрешение
  на сетевой доступ для mDNS-обнаружения устройств (`bonsoir`) и для
  P2P-синка метаданных (`crdt_sync`, порт 8541 по умолчанию) — нужно
  разрешить как минимум для приватных/домашних сетей.
- Готового `.msix`/инсталлятора нет — `flutter build windows` даёт
  папку с exe и dll, для распространения потребуется дополнительная
  упаковка (например, `msix` пакет через одноимённый Dart-пакет) —
  не сделано, вне текущего MVP-объёма.
