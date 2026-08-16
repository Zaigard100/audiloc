# 0032. Единый профильный тумблер синхронизации воспроизведения и настройка фонового режима

## Контекст

Запрос из трёх связанных частей:

1. Заменить два независимых, device-local тумблера "отправлять"/"принимать"
   состояние воспроизведения (docs/adr/0029-playback-state-sync.md) на
   **один**, общий для всего профиля — включил на одном устройстве,
   включено везде после синка.
2. При включении этой синхронизации показывать ещё один тумблер —
   "работать в фоне", чтобы синк и удалённое управление
   (docs/adr/0030-remote-playback-control.md) продолжали работать, даже
   когда устройство не на экране.
3. (Отдельная, гораздо более крупная часть того же запроса) —
   Spotify-Connect-подобный режим: в любой момент воспроизведение реально
   идёт только на одном устройстве профиля, с ручной передачей
   воспроизведения из полноэкранного плеера. Эта часть — самостоятельная
   работа поверх сделанного здесь и в этом ADR не описывается; см. план
   реализации ("Часть C") для протокола владения/хендоффа, который будет
   задокументирован отдельным ADR 0033, когда будет реализован.

Этот ADR фиксирует только первые две части.

## Решение

### 1. Единый профильный тумблер (CRDT, не device-local)

Раньше `sendPlaybackStateSync`/`receivePlaybackStateSync` были двумя
отдельными булями в device-local `settings.json`
(`AppSettingsStore`) — каждое устройство решало за себя, и значение
нигде не было видно другим устройствам того же профиля.

Теперь это одно значение, синкающееся как обычная CRDT-строка — новая
таблица `profile_settings` (`lib/data/db/audiloc_database.dart`, версия
схемы 6), один ряд `id = 'current'`, колонка
`sync_playback_enabled INTEGER`, по образцу уже существующей
`playback_state` (ADR 0029): будучи обычной CRDT-строкой, включение на
одном устройстве само доезжает до всех остальных через тот же
merge-канал, который уже переносит `tracks`/`favorites`/`playlists` —
никакой отдельной логики распространения не понадобилось.

`lib/data/repositories/profile_settings_repository.dart`
(`ProfileSettingsRepository`) — `watchSyncPlaybackEnabled()` (для UI),
`isSyncPlaybackEnabled()` (одноразовое чтение), `setSyncPlaybackEnabled(bool)`.
`profileSyncEnabledProvider` (`core/providers.dart`) — `StreamProvider<bool>`
поверх `watch...()`, заменяет оба старых `current
Send/ReceivePlaybackStateSyncProvider`. Пишется прямо из UI
(`ref.read(profileSettingsRepositoryProvider).setSyncPlaybackEnabled(value)`)
— это CRDT-запись, а не device-level настройка, поэтому ей не нужна
`changeXProvider`/`AudilocApp` прокидка, которой пользуются
device-level тумблеры (`allowRemoteControl` и новый
`keepAliveInBackground`, см. ниже).

`PlaybackStateWriter` (`lib/services/playback/playback_state_writer.dart`)
не менялся — его конструктор всё так же принимает `isSendEnabled: bool
Function()`, просто в `player_providers.dart` он теперь читает
`ref.read(profileSyncEnabledProvider).value ?? false` вместо старого
провайдера. `resume_playback_prompt.dart`'s приёмный гейт, наоборот,
**не** читает `profileSyncEnabledProvider.value` напрямую: та проверка
выполняется из `fireImmediately: true`-слушателя, который может
сработать раньше, чем `StreamProvider`'s CRDT-watch успеет прислать
первое значение (тогда `.value` — `null`, гейт молча читался бы как
`false`, и входящее состояние терялось бы даже при включённом синке).
Вместо этого — одноразовый `await
ref.read(profileSettingsRepositoryProvider).isSyncPlaybackEnabled()`,
без этой гонки.

Настройка помечена экспериментальной в подписи — то же наследие, что и
у исходных двух тумблеров (ADR 0029's регрессионный лог).

### 2. Тумблер "работать в фоне" — device-local, условно видимый

В отличие от тумблера синка, это способность конкретного устройства
(держать процесс/уведомление активным), а не профиля целиком — поэтому
он остался device-local, тем же путём, что и `allowRemoteControl`
(ADR 0030): `AppSettingsStore.keepAliveInBackground()`/
`setKeepAliveInBackground()` (default `false`),
`change/currentKeepAliveInBackgroundProvider` в `core/providers.dart`,
параметры `openProfileSession`, поле+метод в `lib/app.dart` — четвёртая
копия уже трижды использованного паттерна.

В Settings (`_KeepAliveInBackgroundToggle`,
`lib/features/settings/settings_screen.dart`) он рендерится условно,
сразу под тумблером синка:
`if (!(ref.watch(profileSyncEnabledProvider).value ?? false)) return const SizedBox.shrink();`
— вне режима синхронизации держать процесс в фоне незачем.

**Платформенный эффект тумблера — Android foreground-уведомление вне
активного воспроизведения и трей на десктопе — в этот заход не входит.**
Тумблер существует, персистится и корректно показывается/скрывается,
но пока не подключён ни к какому платформенному механизму: это
отдельная работа (для десктопа потребует новых зависимостей —
`tray_manager`/`window_manager`, которых сейчас нет в `pubspec.yaml`,
и не может быть проверена без реального устройства/окна), которая
дополнит этот ADR или получит собственный, когда будет сделана.

## Файлы

Новые: `lib/data/repositories/profile_settings_repository.dart`.

Изменённые: `lib/data/db/audiloc_database.dart` (`+profile_settings`,
версия схемы 6), `lib/core/providers.dart`
(`+profileSettingsRepositoryProvider`, `+profileSyncEnabledProvider`,
`+change/currentKeepAliveInBackgroundProvider`, убраны
`change/current{Send,Receive}PlaybackStateSyncProvider`),
`lib/core/profile_session.dart`, `lib/app.dart`,
`lib/data/settings/app_settings_store.dart`
(`+keepAliveInBackground`, убраны `send/receivePlaybackStateSync`),
`lib/features/player/providers/player_providers.dart`,
`lib/features/player/widgets/resume_playback_prompt.dart`,
`lib/features/settings/settings_screen.dart`
(`_SendPlaybackStateSyncToggle`+`_ReceivePlaybackStateSyncToggle` →
`_SyncPlaybackStateToggle`, `+_KeepAliveInBackgroundToggle`),
`lib/l10n/app_ru.arb`/`app_en.arb` (+`lib/l10n/gen/*`, regenerated),
`test/unit/core/profile_session_test.dart`,
`test/widget/resume_playback_test.dart`.

## Верификация

1. `flutter analyze` — 0 ошибок.
2. `flutter test test/unit/ test/widget/` — зелёные (за вычетом
   `profile_session_test.dart`/`sync_orchestrator_test.dart`'s
   намеренного использования реального `metadataSyncPort = 8541`,
   который конфликтует, если на машине уже запущен обычный экземпляр
   приложения — не регрессия этого изменения).
3. Живая проверка (обязательна для CRDT-распространения, как и для
   всех предыдущих sync-ADR): включить тумблер на устройстве 1 →
   появляется включённым на устройстве 2 после синка; тумблер
   "работать в фоне" появляется только при включённом синке и исчезает
   при выключении — не выполнялась в этом заходе, платформенный эффект
   ещё не реализован.
