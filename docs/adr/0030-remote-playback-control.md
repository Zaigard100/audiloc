# 0030. Удалённое управление воспроизведением на сопряжённых устройствах

## Контекст

Запрос: управлять плеером другого уже сопряжённого устройства прямо с
этого — play/pause/next/prev, полоса прогресса (только отображение),
плюс долгий тап по устройству → "запустить то, что у меня на паузе"
(взять текущий трек+позицию управляющего устройства и запустить на
целевом) или "выбрать трек и запустить". Обязательное условие:
устройство само решает, разрешает ли собой управлять — локальная,
несинхронизируемая настройка (как тема/язык), по умолчанию **выключена**
— иначе любое уже сопряжённое устройство могло бы менять то, что играет
где угодно, без спроса.

Обычный CRDT-синк (`playback_state`, ADR 0029) сюда не годится — он
синкает с задержкой и только по паузе, а "нажал play — должно заиграть
сейчас" требует живого канала. Выбран WebSocket, отдельный сервис — по
образцу уже существующих `PairingService`/`ShareService`
(`lib/services/sync/pairing/*`, `lib/services/sync/share/*`), но вместо
HTTP POST-запросов — один WebSocket на подключение через `dart:io`'s
`WebSocketTransformer.upgrade` (сервер) и `WebSocket.connect` (клиент) —
оба входят в `dart:io`, никаких новых зависимостей.
`web_socket_channel` в `pubspec.yaml` объявлен для `crdt_sync`'s
внутреннего использования, но нигде в `lib/` не импортируется напрямую —
не трогаем его, чтобы не завести два способа делать одно и то же.

## Протокол

Новый порт `remoteControlPort = 8546` (`lib/core/providers.dart`,
следующий свободный после 8541–8545). `RemoteControlServer`
(`lib/services/remote_control/remote_control_server.dart`) слушает
всегда, на каждом устройстве — доступность зависит не от того, поднят
ли сервер, а от проверки на каждое подключение.

Обмен — JSON-сообщения по одному сокету:

1. Клиент шлёт `{"type":"hello","deviceId":...,"name":...}` первым
   сообщением.
2. Сервер проверяет: `deviceId` есть в локальной `devices`
   (`DevicesRepository.byId` — уже сопряжено с этим профилем, не просто
   заявлено в hello) **и** `isAllowed()` (колбэк, читает
   `currentAllowRemoteControlProvider` заново на каждое подключение, не
   один раз при старте сервера — тот же паттерн, что уже есть у
   `PairingService`'s `canJoinDifferentProfile`). Если нет — шлёт
   `{"type":"rejected"}` и закрывает сокет.
3. Если да — `{"type":"accepted"}`, дальше сервер сам пушит
   `{"type":"state", trackId, title, artist, positionMs, durationMs,
   isPlaying}` на каждое изменение трека/play-paused и раз в секунду по
   таймеру для позиции (не на каждый тик — тот же урок про
   write/push-storm, что уже применялся к `playback_state`, ADR 0029).
   Клиент шлёт команды `{"type":"command","action":"play"|"pause"|"next"|"previous"}`
   или `{"type":"command","action":"loadAndPlay","trackId":...,"positionMs":...}`
   — последняя резолвит трек через `TracksRepository.byId`, и если
   `!track.isAvailableLocally`, отвечает
   `{"type":"error","reason":"track_not_available"}` вместо каких-либо
   попыток передать сам файл по сети (трек должен быть уже локально —
   та же модель, что и везде в приложении, см. ADR 0010).

Реализационная деталь, из-за которой пришлось переделывать первый
черновик и клиента, и сервера: `dart:io`'s `WebSocket` —
single-subscription, `.listen()` можно вызвать только один раз. Черновик
читал hello-сообщение через `socket.first`, а затем отдельно вызывал
`socket.listen(...)` для команд — второй вызов бросает исключение.
Исправлено: **один** персистентный `listen()` на весь сокет с самого
начала, и hello, и команды разбираются в одном и том же коллбэке
(флаг `helloReceived` различает первое сообщение от последующих) — то
же самое сделано в клиенте для разбора `accepted`/`rejected`/`state`.

## Настройка "разрешить удалённое управление"

Устройство-уровня, не в CRDT — тот же принцип, что тема/язык/шорткаты
(ADR 0028, ADR 0029). `AppSettingsStore.allowRemoteControl()`/
`setAllowRemoteControl()`, дефолт `false`. Прокидка — тот же путь, что
уже применялся трижды: `changeAllowRemoteControlProvider`/
`currentAllowRemoteControlProvider` в `core/providers.dart`, параметры
`openProfileSession`, поле+метод в `lib/app.dart`. Переключатель — в
`SettingsScreen`, в секции "Воспроизведение".

## Провайдеры и жизненный цикл

`lib/features/devices/providers/remote_control_providers.dart`:

- `remoteControlControllerProvider` (`Provider.autoDispose.family<..., String>`
  по `deviceId`) — держит `RemoteControlClient` и методы
  `play()/pause()/next()/previous()/loadAndPlay()`, которые `DeviceTile`
  вызывает напрямую через `ref.read(...)`.
- `remoteControlConnectionProvider` (`StreamProvider.autoDispose.family`)
  — резолвит host/port через уже существующий `nearbyPeersProvider`
  (`.select` только на запись конкретного `deviceId`, не на всю карту —
  иначе онлайн/офлайн любого стороннего устройства пересоздавал бы
  соединение), запускает `client.connect()`, отдаёт статус
  (`connecting`/`accepted`/`rejected`) + поток `RemoteState`.

`.autoDispose` здесь принципиален и не по умолчанию: `family`-провайдеры
без явного `.autoDispose` в Riverpod живут вечно (уже так у
`playlistItemsProvider` — некритично для ограниченного числа плейлистов,
но для сокета, который создаётся при каждом взгляде на `DeviceTile`,
было бы утечкой). С `.autoDispose` соединение живёт ровно пока
соответствующий `DeviceTile` на экране.

## UI

`DeviceTile` (`lib/features/devices/widgets/device_tile.dart`): для
online-устройства смотрит `remoteControlConnectionProvider(device.id)`;
если статус `accepted` — под основным `ListTile` появляется
компактный ряд play/pause/next/prev + `LinearProgressIndicator`
(**не** `Slider` — только отображение, без перемотки, явное требование
запроса) и заголовок текущего трека. Долгий тап (и правый клик на
десктопе — тот же `GestureDetector.onSecondaryTap`, что уже используют
`TrackTile`/`PlaylistTile`) открывает
`lib/features/devices/widgets/device_actions_sheet.dart`:

- **"Запустить то, что у меня на паузе"** — `playerService.currentTrack`/`.position`
  **этого** устройства (не через `ref.read(currentTrackProvider)` — та
  же ловушка Riverpod 3 "StreamProvider на паузе без активного
  слушателя", уже исправленная для `hasLocalTrack` в ADR 0029, здесь
  обойдена тем же способом — прямое синхронное поле
  `PlayerService.currentTrack`); неактивен, если ничего не загружено.
- **"Выбрать трек и запустить"** —
  `lib/features/devices/widgets/remote_track_picker_sheet.dart`,
  список треков, отфильтрованный новым `TracksRepository.availableOnDevice(nodeId)`
  (join по `track_locations` — по образцу уже существующего
  `peersWithLocalCopy`) до того, что целевое устройство реально имеет
  локально, чтобы не предлагать треки, которые там заведомо не
  воспроизведутся.

## Файлы

Новые: `lib/services/remote_control/remote_control_models.dart`,
`remote_control_server.dart`, `remote_control_client.dart`,
`lib/features/devices/providers/remote_control_providers.dart`,
`lib/features/devices/widgets/device_actions_sheet.dart`,
`remote_track_picker_sheet.dart`,
`test/unit/services/remote_control_test.dart` (реальные WS-раунд-трипы
по localhost — принят/отклонён по непарности и по выключенной
настройке, live-пуш состояния, все команды, `track_not_available`).

Изменены: `lib/data/repositories/tracks_repository.dart`
(`+availableOnDevice`), `lib/data/settings/app_settings_store.dart`
(`+allowRemoteControl`), `lib/core/providers.dart` (`+remoteControlPort`,
`+remoteControlServerProvider`, `+change/currentAllowRemoteControlProvider`),
`lib/core/profile_session.dart` (`+` параметры, старт/dispose),
`lib/app.dart` (тот же паттерн, что для темы/языка/шорткатов),
`lib/features/settings/settings_screen.dart` (`+SwitchListTile`),
`lib/features/devices/widgets/device_tile.dart` (`+onLongPress`,
`+onSecondaryTap`, `+` инлайн-контролы), `lib/l10n/app_ru.arb`/`app_en.arb`.

## Верификация

1. `flutter analyze` — 0 ошибок.
2. `flutter test test/unit/` — новый `remote_control_test.dart` (7
   тестов) зелёный вместе с остальными.
3. `flutter test test/widget/` — существующие проходят без изменений.
4. `flutter build linux` и `flutter build apk --debug` — успешно.
5. Живая проверка (обязательна — то, что автотесты в этой среде
   принципиально не могут покрыть, реальная многоустройственная сеть):
   включить "разрешить удалённое управление" на одном устройстве,
   оставить выключенным на другом; на устройстве без включённой
   настройки у остальных участников управление не появляется вообще; на
   включённом — play/pause/next/prev + полоса прогресса появляются у
   других сопряжённых устройств; "запустить то, что у меня на паузе" и
   "выбрать трек" реально переключают и играют на целевом устройстве с
   нужной позиции.
