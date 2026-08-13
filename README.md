# AudiLoc

Кроссплатформенный (Linux/Windows/Android) музыкальный плеер с
автоматической P2P-синхронизацией библиотеки (треки, теги, избранное,
плейлисты) между устройствами в локальной сети — без облака и без
центрального сервера. Полное ТЗ: [`tz-p2p-music-app.md`](tz-p2p-music-app.md).

Статус: MVP. Этапы 0–1 (UI, локальное воспроизведение, локальное
CRDT-хранилище) реализованы и покрыты тестами; этапы 2–4 (P2P-синк
метаданных, встроенная передача файлов, дедупликация) — рабочий код,
проверенный в том числе на двух реальных устройствах (Linux + Android).
Подробности и явные ограничения: [`docs/roadmap.md`](docs/roadmap.md).

## Возможности

- Библиотека: импорт папки → авто-извлечение тегов и обложек → sha256
  файла как id трека (идемпотентный повторный импорт).
- Плеер: мини-плеер снизу + полноэкранный (свайп вверх/тап), очередь,
  избранное — офлайн-first, без ожидания сети. На Android — уведомление
  воспроизведения, управление с лок-скрина и кнопки гарнитуры/Bluetooth
  (`audio_service`, `lib/services/playback/audiloc_audio_handler.dart`).
- Плейлисты: создание, добавление/удаление треков, порядок с
  дробным индексом (docs/data-model.md).
- Устройства: список известных узлов с online/offline, QR-код id
  устройства для добавления, ручной и автоматический синк при
  обнаружении узла в LAN, бейдж "синхронизировано N изменений".
- Передача файлов — встроенная, без сторонних программ: HTTP-сервер
  и клиент AudiLoc сами докачивают недостающие треки с online-пиров
  в локальной сети, с докачкой при обрыве (docs/adr/0010).

## Архитектура

Подробно — [`docs/architecture.md`](docs/architecture.md) (со
схемами) и [`docs/data-model.md`](docs/data-model.md) (таблицы БД).
Обоснование ключевых решений и выбора пакетов — [`docs/adr/`](docs/adr/).

Коротко: Flutter (Riverpod, go_router) + `media_kit` для
воспроизведения + `sqlite_crdt`/`crdt_sync` (cachapa) для CRDT-слоя
метаданных и P2P-синка + `bonsoir` для mDNS-обнаружения + собственный
HTTP-сервер/клиент (`dart:io`/`dio`) для передачи файлов —
самодостаточно, без сторонних программ (docs/adr/0010).

## Установка и запуск

### Требования

- Flutter SDK (stable), Dart идёт в комплекте.
- **Linux desktop**: системные `clang`, `cmake`, `ninja`, `pkg-config`,
  `gtk+-3.0`, `mpv` (для `media_kit`). На Arch/CachyOS:
  `sudo pacman -S clang cmake ninja pkgconf gtk3 mpv`; на
  Debian/Ubuntu — `sudo apt install clang cmake ninja-build
  pkg-config libgtk-3-dev libmpv-dev`.
- **Android**: Android SDK/NDK — полная инструкция:
  [`docs/building-android.md`](docs/building-android.md).
- **Windows**: Visual Studio с C++ workload — полная инструкция:
  [`docs/building-windows.md`](docs/building-windows.md) (сборка
  возможна только на самой Windows, кросс-компиляция с Linux
  недоступна).

Никаких сторонних программ ставить не нужно — передача файлов
встроена в само приложение.

### Команды

```bash
flutter pub get

# Статический анализ
flutter analyze

# Тесты: все unit-тесты разом
flutter test test/unit/

# Тесты: каждый widget-тест по отдельности — см. docs/testing-notes.md
# (у `flutter test` без аргументов в этой Flutter-сборке есть известное
# зависание shutdown-процесса после реальных записей в sqflite)
flutter test test/widget/mini_player_test.dart
flutter test test/widget/track_tile_test.dart
flutter test test/widget/library_screen_test.dart

# Запуск на Linux desktop
flutter run -d linux

# Сборка Linux-бинаря
flutter build linux
```

Сборка под Android и Windows требует своей платформенной подготовки
(SDK/NDK, Visual Studio) — подробные пошаговые инструкции:
[`docs/building-android.md`](docs/building-android.md),
[`docs/building-windows.md`](docs/building-windows.md).

Android/Windows-сборки (`flutter build apk` / `flutter build
windows`) не проверялись в среде, где писался этот код (нет Android
SDK и нет Windows/кросс-тулчейна) — см. `docs/roadmap.md`.

## Тесты

- `test/unit/data/` — репозитории (`TracksRepository`,
  `FavoritesRepository`, `PlaylistsRepository`) на
  `SqliteCrdt.openInMemory()`: CRUD, soft-delete/восстановление,
  дробный порядок плейлиста.
- `test/unit/services/` — эвристика дедупликации, импорт библиотеки
  (реальное sha256-хеширование + фейковый `TagReader`), **реальный**
  P2P-роундтрип `crdt_sync` между двумя in-memory узлами по
  настоящему localhost-сокету, и **реальный** HTTP round-trip
  передачи файла между `FileTransferServer`/`FileTransferClient`
  (включая докачку прерванного файла).
- `test/widget/` — мини-плеер, тайл трека (офлайн-first тоггл
  избранного), экран библиотеки (пустое состояние / список).

Все тесты проходят; про то, почему их стоит запускать директориями/файлами,
а не одним голым `flutter test` в этой конкретной среде — см.
[`docs/testing-notes.md`](docs/testing-notes.md).

## Структура репозитория

```
lib/            — код приложения (core/ data/ services/ features/)
test/           — unit- и widget-тесты
docs/           — архитектура, модель данных, ADR, roadmap
tz-p2p-music-app.md — исходное ТЗ
```
