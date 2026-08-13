# 0002. `audiotags` вместо `id3` для чтения/записи тегов

## Контекст

ТЗ называет пакет `id3` (чистый Dart) для чтения ID3-тегов. При
проверке на pub.dev выяснилось, что пакет **discontinued** с 2021
года (последняя версия 1.0.2), поддерживает только MP3 и не имеет
API для записи тегов (нужна для будущего редактирования жанра/тегов
из приложения).

## Решение

Использовать `audiotags` (github.com/erikas-taroza/audiotags) —
активно поддерживаемый плагин на `flutter_rust_bridge` поверх
`lofty-rs`, с чтением **и** записью тегов, обложек, поддержкой
MP3/FLAC/OGG/M4A/WAV и явной поддержкой Android/iOS/Linux/macOS/
Windows в `pubspec.yaml` плагина.

## Последствия

- `TagReader` (lib/services/library_import/tag_reader.dart) — тонкая
  обёртка, изолирующая весь остальной код от конкретного пакета:
  замена на другой источник тегов в будущем не потребует трогать
  `LibraryImportService`.
- `audiotags` — нативный FFI-плагин, поэтому не грузится в чистом
  `flutter test` — тесты `LibraryImportService` подменяют `TagReader`
  фейком (см. test/unit/services/library_import_service_test.dart),
  а не мокают DevTools/платформенные каналы.
- Поле `duration` в `audiotags.Tag` трактуется как целые секунды
  (типично для lofty-подобных библиотек) и переводится в мс; это
  best-effort значение только для отображения в списке до начала
  воспроизведения — `media_kit` сообщает точную длительность в
  процессе игры.
