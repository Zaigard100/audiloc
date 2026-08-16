# 0033. Эксклюзивность воспроизведения, хендофф и управление из плеера

## Контекст

Третья, самая крупная часть запроса, продолжающего ADR 0032: в любой
момент воспроизведение реально идёт только на одном устройстве профиля
(играет на телефоне — на остальных 100% не играет), с ручной передачей
воспроизведения на другое устройство прямо из полноэкранного плеера (не
из вкладки "Устройства") и последующим управлением им оттуда же — по
образцу Spotify Connect. Активно только когда включён единый профильный
тумблер синхронизации (ADR 0032); устройства с выключенным синком в
этой системе не участвуют вообще.

Существующий живой канал (ADR 0030, `RemoteControlServer`/`Client`) не
годится напрямую для эксклюзивности: он асимметричный (контроллер →
цель) и гейтится отдельной, обычно выключенной настройкой "разрешить
удалённое управление" — смешивать её с обязательной эксклюзивностью
значило бы либо сломать её для всех, у кого тот тумблер выключен, либо
тихо обойти его смысл. CRDT-синк (ADR 0029) тоже не годится — лагает и
синкает только по паузе.

## Протокол владения

Новый, отдельный от ADR 0030 живой канал, порт `playbackOwnershipPort =
8547`: `lib/services/playback_ownership/`.

- `playback_ownership_models.dart` — `OwnershipMessage` (sealed):
  `OwnershipClaim{deviceId,claimId,reason}` (`claimId =
  '<millis>-<deviceId>'`, напрямую сравнимый — `compareTo`, больший
  millis побеждает, при равенстве — лексикографическое сравнение
  `deviceId`), `OwnershipClaimAck`/`OwnershipClaimReject`,
  `OwnershipOwner{deviceId|null,since}` (госсип), `OwnershipHeartbeat`
  (каждые 2с).
- `playback_ownership_link.dart` — `PlaybackOwnershipLink`, симметричное
  установленное соединение (не controller/target, как у ADR 0030).
  **Не** делает свой `socket.listen()` — `dart:io`'s `WebSocket`
  терпит ровно один `.listen()` за всё время жизни сокета (тот же урок,
  что ADR 0030 уже поймал); сервер/клиент конструируют `Link` изнутри
  своего единственного персистентного `listen()`-колбэка hello-рукопожатия
  и дальше прокидывают сообщения через `handleIncoming`/`handleClosed`.
  `onLost` — не конструкторный, а settable-филд: линк создаётся раньше,
  чем координатор успевает его получить, и присваивает колбэк сразу по
  получении. Следит за живостью сам: heartbeat раз в 2с, `onLost` при
  отсутствии *любых* сообщений 6с (3 пропущенных heartbeat'а — то же
  окно, что `PeerPresenceTracker`'s `PeerLost`, ADR 0025). `dispose()`
  сразу ставит внутренний флаг "потерян" — иначе асинхронно
  завершающееся закрытие сокета могло вызвать `onLost()` ещё раз, уже
  после того как владелец колбэка (координатор) сам разобран (реальный
  баг, пойманный именно тестами на этом ADR — см. "Верификация").
- `playback_ownership_server.dart` / `playback_ownership_client.dart` —
  hello/accept: паспорт как в ADR 0030 (`DevicesRepository.byId` +
  свежая проверка), но гейт — только профильный `isSyncEnabled()`, не
  "разрешить удалённое управление".
- `playback_ownership_coordinator.dart` — `PlaybackOwnershipCoordinator`,
  держит связь со **всеми** онлайн, сопряжёнными, sync-enabled
  устройствами всё время, пока синк включён (как `SyncOrchestrator`, а
  не как ADR 0030's "только пока открыт `DeviceTile`"). Dial-out дедуп
  — тот же "меньший `deviceId` дозванивается", что и в ADR 0025.
  Реагирует на смену профильного тумблера (`ProfileSettingsRepository.watchSyncPlaybackEnabled()`
  напрямую, не через riverpod — сервисный слой этого файла остаётся
  riverpod-агностиком): включили — дозванивается уже известным онлайн
  пирам (`PeerFound` не перевызывается заново только потому что
  тумблер включили); выключили — рвёт все линки и сбрасывает
  владение.
  - `claimSelf({reason})` — реактивный, неподтверждаемый claim ("я
    только что начал играть" или "заберите обратно на это устройство"
    — оба случая, нет третьей стороны для ack), broadcast всем линкам,
    оптимистично сразу считает себя владельцем.
  - `claimForDevice(targetId)` — целевой хендофф, ждёт
    ack/reject/таймаут 3с, владение выставляется только по факту ack.
  - Приём `claim{deviceId:X}` (X — не я) на устройстве, считавшем себя
    владельцем: сравнение с собственным `_selfClaim` через `compareTo`
    — если входящий выигрывает (обычный случай — просто "более новый"
    claim, либо настоящая гонка одновременных claim'ов), синхронно
    `playerService.pause()` + владение переходит X; если я выигрываю —
    просто игнорирую, пир независимо придёт к тому же выводу из моей
    копии его собственного claim'а и сам паузится.
  - Приём targeted claim (`deviceId == self`) — безусловный
    ack+становлюсь владельцем (если синк включён), плюс запоминаю
    `lastHandoffInitiator` (см. ниже).
  - Потеря линка (heartbeat-таймаут **и** mDNS `PeerLost`, оба 6с) →
    владение `null`, **не** переходит автоматически к живым — следующий
    нажавший play становится владельцем через обычный claim.

`OwnershipClaimingPlayerService` (`ownership_claiming_player_service.dart`)
— декоратор `PlayerService`, делегирует всё 1:1, кроме `play()`,
резюмирующего `playOrPause()` и `setQueue(autoPlay:true)` — перед
делегированием, если синк включён, fire-and-forget
`coordinator.claimSelf()`. `playerServiceProvider` оборачивается им
безусловно; чтобы не завести цикл провайдеров (координатору тоже нужен
плеер — вызвать `pause()` при проигрыше claim'а), заведён отдельный
`rawPlayerServiceProvider` — координатор зависит от него, а не от
уже-декорированного `playerServiceProvider`.

## Хендофф и режим плеера

Значок "cast" в `AppBar` полноэкранного плеера (виден только при
включённом синке) открывает `playback_target_picker_sheet.dart` —
список: сопряжённые устройства, до которых у координатора сейчас есть
живой линк (`coordinator.linkedDeviceIds`) — то есть подтверждённо
sync-enabled прямо сейчас, не просто когда-то сопряжённые — плюс
закреплённое "Это устройство".

Выбор удалённого `T`: собрать очередь+позицию (`resolveQueueTracks`,
уже существующий из ADR 0030) → `coordinator.claimForDevice(T)` → по
успеху дождаться, пока `remoteControlConnectionProvider(T)` реально
примет соединение (`ref.listenManual`, тот же паттерн, что
`awaitFirstValue`, — `.autoDispose`-провайдер иначе не проживёт
достаточно долго для голого `ref.read`) → `loadAndPlay(...)` →
локально `pause()`. Ошибка/таймаут/отказ на любом шаге — локальное
воспроизведение не трогается вообще.

`RemoteControlServer.isAllowed` стал `bool Function(String
callerDeviceId)` — доп. путь принятия: обычный тумблер "разрешить
удалённое управление" **или** звонящий — это `coordinator.lastHandoffInitiator`
(устройство, которое только что передало этому владение). Явный ack
хендоффа сам по себе уже есть согласие быть управляемым именно этим
инициатором — независимо от отдельного тумблера ADR 0030.

`RemoteCommand` пополнился `RemoteSeek` — Devices-tab'овские
быстрые контролы (ADR 0030) сознательно без перемотки (только
отображение прогресса), но полноэкранный плеер их для управления
удалённым устройством уже показывает.

### `ActivePlaybackController`

`lib/features/player/providers/{playback_ownership_providers,
active_playback_controller}.dart`. `activePlaybackTargetProvider`
(`LocalPlaybackTarget`/`RemotePlaybackTarget(deviceId,name)`) следует
за `coordinator.currentOwner`; без синка или без владельца —
`LocalPlaybackTarget`. `ActivePlaybackController` — используется
**только** `full_player_screen.dart`, маршрутизирует
play/pause/playOrPause/seek/next/previous в `playerServiceProvider`
или `remoteControlControllerProvider(deviceId)` по текущей цели.
Сознательно не трогаем смысл `playerServiceProvider` глобально — иначе
сломался бы ADR 0030's контракт "устройство-цель всегда сообщает и
управляет только своим локальным плеером" для мини-плеера, шорткатов,
`PlaybackStateWriter`, входящего удалённого управления с других
устройств. Шафл/повтор в удалённом режиме задизейблены — нет
эквивалента на проводе, и не было запроса добавлять его сейчас.

**Возврат на себя ("Это устройство")** — сознательно урезанная v1:
`coordinator.claimSelf()` + восстановление **только текущего трека**
(`RemoteState.trackId`/`positionMs`, `setQueue([track], ...)`), не
всей очереди устройства-владельца — `RemoteState` сегодня не несёт
список очереди. Это тот же класс регрессии, что ADR 0030 уже ловил и
чинил для прямого направления (`loadAndPlay` с одним треком оставлял
next/previous без цели) — здесь она осознанно оставлена для обратного
направления как честный, задокументированный компромисс под объём
этого захода, а не забытый баг. Следующий шаг: добавить
`RemoteState.queueTrackIds`/`.queueIndex`, заполняемые
`_RemoteConnection` из очереди устройства-владельца, и переиспользовать
их здесь так же, как `loadAndPlay` уже переиспользует свою логику
резолва очереди.

## Файлы

Новые: `lib/services/playback_ownership/*`,
`lib/features/player/providers/{playback_ownership_providers,
active_playback_controller}.dart`,
`lib/features/player/widgets/playback_target_picker_sheet.dart`,
`test/unit/services/playback_ownership_coordinator_test.dart`.

Изменённые: `remote_control_models.dart` (`+RemoteSeek`),
`remote_control_server.dart`/`_client.dart`/`remote_control_providers.dart`
(`+seek`, `isAllowed` берёт `callerDeviceId`), `core/providers.dart`
(`+playbackOwnershipPort/-ServerProvider/-CoordinatorProvider`,
`+rawPlayerServiceProvider`, `playerServiceProvider` оборачивается в
`OwnershipClaimingPlayerService`), `profile_session.dart` (старт/dispose
новых сервисов), `full_player_screen.dart` (значок cast, все контролы
через `ActivePlaybackController`), `test/unit/services/remote_control_test.dart`
(сигнатура `isAllowed`).

Не трогаем: `player_service.dart`'s контракт, `media_kit_player_service.dart`,
`player_providers.dart`, `mini_player.dart`, `playback_shortcuts.dart`,
`resume_playback_prompt.dart`, `local_session_restore.dart`, всё под
`devices/widgets/` — ADR 0030's функциональность во вкладке
"Устройства" работает как есть, без пересечения с этим режимом.

## Верификация

1. `flutter analyze` — 0 ошибок.
2. `flutter test test/unit/` — новый
   `playback_ownership_coordinator_test.dart` (7 тестов, реальные
   WS-раунд-трипы: два узла на разных loopback-адресах, один разделяемый
   порт, как в проде — установление ровно одного линка, claim
   распространяется и виден другой стороной, чужой claim принудительно
   паузит текущего владельца, целевой хендофф ждёт ack, отказ при
   выключенном на цели синке, claim на несуществующий линк не трогает
   состояние, потеря линка сбрасывает владение в `null`) вместе с
   существующими зелёный.

   Первый черновик ловил две реальные гонки, обе теперь покрыты
   регрессионно: (а) `dart:io`'s `WebSocket` позволяет ровно один
   `.listen()` за жизнь сокета — черновик слушал дважды (hello, потом
   ещё раз внутри `Link`), падал с "Stream has already been listened
   to"; (б) `Link.dispose()` не помечал линк потерянным, поэтому
   асинхронно завершающееся закрытие сокета вызывало `onLost()` ещё
   раз уже на разобранном координаторе — "Cannot add new events after
   calling close".
3. `flutter test test/widget/` — существующие зелёные;
   `mini_player_test.dart`'s навигационный тест обёрнут в
   `tester.runAsync` — полноэкранный плеер теперь делает настоящий
   CRDT/sqflite-запрос (`profileSyncEnabledProvider`), которому нужен
   реальный, а не fake-async, event loop, чтобы не оставлять висящий
   таймер к концу теста (тот же паттерн, что уже применяют
   `resume_playback_test.dart`/`local_session_restore_test.dart`).
4. Живая проверка на реальных устройствах (обязательна, не выполнялась
   в этом заходе): запуск музыки на одном устройстве реально паузит
   другое при попытке заиграть там же; хендофф из плеера реально
   переносит звук с той же позиции; управление из плеера в удалённом
   режиме (play/pause/next/prev/seek) реально доходит; возврат "на это
   устройство" восстанавливает трек (без остальной очереди — см.
   ограничение выше); выключение сети/убийство процесса на
   владельце — через ~6с у остальных владение сбрасывается.
