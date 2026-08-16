# 0031. Полноэкранный плеер свайпом вниз/вверх, случайный порядок и повтор

## Контекст

Запрос: свайпом вверх вытягивать полноэкранный плеер ("Сейчас играет"),
свайпом вниз — сворачивать обратно; там же — переключалки "играть
случайные треки" (из текущей очереди — плейлиста или библиотеки),
"играть по кругу" (конец очереди → снова первый трек, **включено по
умолчанию**) и "повторять текущий трек".

Свайп вверх с мини-плеера на полноэкранный уже работал
(`MiniPlayer`'s `GestureDetector.onVerticalDragEnd`, весь виджет без
вложенного скролла — конфликтов с жестом нет). Свайп вниз для закрытия
не хватало.

## Свайп вниз — почему не `GestureDetector.onVerticalDragEnd`

`FullPlayerScreen`'s тело — `SingleChildScrollView` (нужен как fallback
для коротких viewport'ов — маленькие окна на десктопе, альбомная
ориентация на телефоне). Обёртка всего экрана в `GestureDetector` с
`onVerticalDragEnd` конкурировала бы с вложенным `Scrollable`'s
собственным drag-распознавателем за тот же жест — и вложенный
`Scrollable`, будучи потомком, надёжно выигрывает арену (получает
события первым при обходе hit-test), даже когда прокручивать
фактически нечего (`ClampingScrollPhysics` всё равно "принимает" жест
на уровне распознавателя, а уже потом клэмпит смещение к нулю). На
практике это значит: свайп вниз просто не срабатывает всякий раз, как
тело оказывается скроллящимся.

Решение — `Listener` (сырые указательные события) вместо
`GestureDetector` вокруг всего экрана. `Listener` не участвует в
арене жестов вообще: он получает каждое событие указателя независимо
от того, кто "выиграл" — так что он закрывает экран, не отбирая ничего
у `Scrollable`. Трекинг: `_dragStartY` на `onPointerDown`, если
`onPointerMove` относительно него ушёл вниз больше чем на 120
логических пикселей — `Navigator.pop()` (`FullPlayerScreen`, теперь
`ConsumerStatefulWidget` вместо `ConsumerWidget` — нужно поле для
`_dragStartY`).

## Случайный порядок и повтор — почему через `media_kit`/mpv напрямую, а не вручную

`media_kit`/libmpv уже умеют и то, и другое на уровне движка:
`Player.setShuffle(bool)` (команды `playlist-shuffle`/`playlist-unshuffle`)
и `Player.setPlaylistMode(PlaylistMode.none|loop|single)` (свойства mpv
`loop-file`/`loop-playlist`). `PlaylistMode` один-в-один ложится на
запрошенные три состояния: `none` = выключено, `loop` = играть по
кругу (весь список), `single` = повторять текущий трек. Довериться
движку значительно проще и надёжнее, чем реализовывать порядок
воспроизведения (случайный проход + wraparound) вручную в Dart:
`next()`/`previous()`/натуральное завершение трека уже без изменений
идут через `_player.next()`/`_player.previous()`/`loop-file` — они
просто начинают учитывать новый порядок/режим сами, никакой
дополнительной логики навигации не нужно.

`PlayerService` не должен утекать типами `media_kit` наружу (это и
есть весь смысл абстракции — виджет-тесты подставляют
`FakePlayerService` без нативной библиотеки libmpv), поэтому заведён
свой `enum PlaybackRepeatMode { off, all, one }`
(`lib/services/playback/player_service.dart`) — назван не `RepeatMode`,
потому что это имя уже занято `package:flutter/material.dart`
(`RepeatMode` из `repeating_animation_builder.dart`) и конфликтует
(`ambiguous_import`).

### Ловушка: `playlist-shuffle` переставляет плейлист мpv, а не `_queue`

`MediaKitPlayerService` до этой правки сопоставлял `_player.stream.playlist`'s
`index` с `_queue[index]`, предполагая, что порядок `_queue`
(наш собственный список `Track`) всегда совпадает с порядком плейлиста
внутри mpv. Команда `playlist-shuffle` это предположение ломает — она
физически переставляет список `Media` внутри самого mpv, и следующее
событие `stream.playlist` приходит уже в новом порядке, а `_queue`
остаётся как был. Починено переиндексацией `_queue` на каждое событие
`stream.playlist`: у каждого `Media` есть `extras: {'trackId': ...}`
(уже было — использовалось для сопоставления трека по id, не по
индексу), и слушатель теперь заново собирает `_queue` из
`playlist.medias` в новом порядке через `_tracksById[extras['trackId']]`
— так что `_queue[index]` всегда соответствует реально следующему на
воспроизведении треку, независимо от перетасовки.

### Ловушка: `open()` (то есть каждый `setQueue()`) сбрасывает shuffle-флаг mpv

Каждый вызов `Player.open()` внутри себя дёргает `stop()`, который
явно сбрасывает внутренний Dart-флаг `isShuffleEnabled` в `false` (и,
поскольку плейлист при этом целиком очищается и грузится заново без
команды `playlist-shuffle`, реально играет уже неперемешанным). Если
это не учитывать, включённый пользователем shuffle молча слетал бы при
каждом новом `setQueue()` (открыл другой плейлист/трек из библиотеки —
и порядок снова последовательный). `loop-file`/`loop-playlist` этому
сбросу не подвержены (это свойства mpv, а не Dart-состояние `stop()`),
так что режим повтора остаётся как был без дополнительного кода.
`MediaKitPlayerService` держит собственный `_shuffleEnabled` как
источник истины и переприменяет его (`_player.setShuffle(true)`) сразу
после `open()`, если он был включён — тумблер остаётся "липким" в
рамках сессии, а не сбрасывается на каждый новый выбор трека.

Ни shuffle, ни repeat-режим нигде не сохраняются на диск — оба сессионные,
сбрасываются к дефолту (`shuffle: выключен`, `repeat: all`) на каждый
запуск приложения, как и сама очередь.

## UI

Два `IconButton` в `FullPlayerScreen`, под транспортным рядом
(play/pause/prev/next): `Icons.shuffle` (подсвечен акцентным цветом,
когда включён) и `Icons.repeat`/`Icons.repeat_one` (переключается по
кругу off → all → one → off при каждом нажатии, подсвечен, когда не
`off`). Оба напрямую дёргают `playerServiceProvider().setShuffle(...)`/
`.setRepeatMode(...)` — состояние приходит через два новых
`StreamProvider` (`shuffleEnabledProvider`, `repeatModeProvider`,
`lib/features/player/providers/player_providers.dart`), с fallback на
дефолт (`false`/`all`) до первого события потока — тот же приём, что
уже используется для `isPlayingProvider`.

## Файлы

Изменены: `lib/services/playback/player_service.dart` (+`PlaybackRepeatMode`,
+6 абстрактных членов), `lib/services/playback/media_kit_player_service.dart`
(переиндексация `_queue` по `extras.trackId`, реализация
shuffle/repeat, переприменение shuffle после `open()`),
`lib/features/player/providers/player_providers.dart`
(+`shuffleEnabledProvider`/`repeatModeProvider`),
`lib/features/player/full_player_screen.dart` (`ConsumerStatefulWidget`,
`Listener`-based swipe-down, ряд с shuffle/repeat кнопками),
`lib/l10n/app_ru.arb`/`app_en.arb` (+тултипы), `test/widget/fake_player_service.dart`
и три минимальных `_FakePlayerService`/`_NoopPlayerService` в
`test/unit/` (реализуют новые члены интерфейса).

## Верификация

1. `flutter analyze` — 0 ошибок (в частности — конфликт имён с
   `material.dart`'s `RepeatMode` пойман анализатором и устранён
   переименованием в `PlaybackRepeatMode`).
2. `flutter test test/unit/` и `flutter test test/widget/` — зелёные.
3. Живая проверка (обязательна — жесты и реальное поведение mpv
   автотесты в этой среде не покрывают): свайп вверх с мини-плеера и
   вниз с полноэкранного открывает/закрывает плеер плавно, включая
   случай, когда полноэкранный плеер не скроллится (обычная высота
   окна) и когда скроллится (маленькое окно/альбомная ориентация);
   shuffle реально перемешивает порядок next/previous в рамках текущей
   очереди и остаётся включённым после выбора нового трека из той же
   библиотеки/плейлиста; repeat "все" зацикливает очередь с конца в
   начало; repeat "один трек" зацикливает именно текущий трек, ручное
   next/previous при этом всё равно работает.
