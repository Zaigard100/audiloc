# Заметки о прогоне тестов в этой среде

## Итог

- `flutter analyze`: 0 ошибок.
- `flutter test test/unit/` (40 тестов, все unit-тесты сразу): **все проходят**, ~1 секунда.
- Каждый файл из `test/widget/` (3 файла, 13 тестов): **все проходят** при запуске
  по отдельности (`flutter test test/widget/<file>.dart`).
- `flutter build linux`: сборка проходит успешно.

## Известная проблема именно в этой среде: `flutter test` без аргументов

Запуск `flutter test` вообще без аргументов (весь `test/unit/` + `test/widget/`
одним вызовом) в этой конкретной установке **Flutter 3.47.0 stable**
(`4cf2416426`, собран за ~29 часов до установки — фактически ночная сборка
канала stable) periodически зависает на 50–90 секунд при переходе от
widget-теста, который делает реальную запись в SQLite через
`sqflite_common_ffi`, к следующему файлу/тесту, а затем принудительно
убивается сторожевым таймаутом самого `flutter_tools`:

```
Bad state: Cannot close sink while adding stream.
  package:flutter_tools/src/test/flutter_platform.dart:765
TestDeviceException(Shell subprocess crashed with SIGTERM (-15).)
```

Это происходит **внутри `package:flutter_tools`** (`FlutterPlatform._startTest`),
а не в коде AudiLoc и не в `sql_crdt`/`sqlite_crdt`. Диагностика заняла
значительное время и включала проверку нескольких гипотез, все опровергнуты
экспериментально:

1. ~~Гонка между тапом по избранному и `tearDown`~~ — опровергнуто: тот же
   сбой воспроизводится и при явном ожидании нужного состояния через
   `container.listen`/`Completer`, и при `tester.runAsync`, и при простом
   цикле `pump()`.
2. ~~Конкуренция между параллельно запущенными файлами тестов~~ —
   опровергнуто: воспроизводится и с `--concurrency=1`, и при запуске
   единственного файла с единственным тестом.
3. ~~Плагин `file_picker`~~ — опровергнуто отдельным пробным тестом
   (импорт `file_picker` без использования не вызывает зависания).

Подтверждённая причина: **любой `testWidgets`, выполняющий реальную запись
через `sqflite_common_ffi` (INSERT/UPDATE), оставляет фоновый isolate/поток
пакета в состоянии, которое мешает `flutter_tester` чисto завершиться** —
сам тест при этом проходит (все `expect()` успевают выполниться и не
бросают исключений), зависает только последующее закрытие shell-процесса.
`sqflite_common_ffi` предоставляет `databaseFactoryFfiNoIsolate` — вариант
без фонового isolate, — но `sqlite_crdt` жёстко использует `databaseFactoryFfi`
внутри себя и не даёт подменить фабрику через публичный API, так что этот
обходной путь недоступен без форка/патча `sqlite_crdt`.

## Как проверять надёжно

```bash
# Все unit-тесты разом — стабильно, быстро:
flutter test test/unit/

# Каждый widget-тест по отдельности — стабильно:
flutter test test/widget/mini_player_test.dart
flutter test test/widget/track_tile_test.dart
flutter test test/widget/library_screen_test.dart
```

Если требуется именно один вызов `flutter test` без аргументов (например,
в CI), стоит либо закрепить более раннюю стабильную версию Flutter SDK
(проблема не проверялась на других версиях), либо разбить прогон на
отдельные вызовы, как выше.
