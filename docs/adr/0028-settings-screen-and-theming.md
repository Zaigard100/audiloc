# 0028. Экран "Настройки": тема, язык, стереть все данные, о приложении

## Контекст

Запрос: отдельная кнопка настроек, минимум — тема, смена языка, "Стереть
все данные" (с двойной защитой), "О приложении" (создатель, краткое
описание, лицензия, ссылка на GitHub).

Язык уже был реализован в ADR 0027 как ссылка прямо на экране "О
приложении" — с появлением полноценных "Настроек" её логично туда
перенести, а "О приложении" оставить чисто информационным.

## Решение

### Тема: реальный переключатель, не просто заглушка

До этого ADR у приложения была ровно одна тема — `AppTheme.dark()`, а
каждый экран напрямую читал `AppTheme.surface`/`AppTheme.onSurfaceMuted`
и т.п. как `static const` поля. Простого "добавить `AppTheme.light()` и
кнопку-переключатель" было недостаточно: ни один экран ничего не
*читал* из активной темы — они все были жёстко привязаны к конкретным
константам конкретной (тёмной) палитры. Переключение
`MaterialApp.themeMode` само по себе не перекрасило бы ни один экран.

Исправлено: `AppColors` (`lib/core/theme/app_colors.dart`) —
`ThemeExtension<AppColors>` с полями, которые реально отличаются между
темами (`background`/`surface`/`surfaceHigh`/`onSurface`/
`onSurfaceMuted`/`divider`), плюс `context.colors` — аксессор через
`Theme.of(context).extension<AppColors>()!`. `AppTheme.light()`/`.dark()`
собирают `ThemeData` с соответствующим `AppColors` в `extensions: [...]`.
`accent`/`error` остались `static const` на `AppTheme` — акцентный цвет
не меняется между темами, трогать все `const`-деревья, где он уже
использовался, не было смысла.

Все ~60 обращений к `AppTheme.surface`/`.surfaceHigh`/`.onSurfaceMuted`
по всем `lib/features/**` заменены на `context.colors.*`
(скриптом — вручную дошли до всех оставшихся `const`, которые из-за
этого перестали быть корректными константными выражениями, и убрали
`const` только у них, не трогая соседние). Отдельно вручную поправлены
места, где раньше был захардкожен `Colors.white`/`Colors.white12` и
которые в светлой теме выглядели бы сломанными не будучи частью явной
палитры (`mini_player.dart`'s progress track/divider/play-button,
`search_screen.dart`'s текст поля поиска) — оставлены как есть только
там, где `Colors.white` в обеих темах корректен по смыслу (белый текст
поверх фиксированно-акцентной или тёмного затемнённого фона — обложка
плейлиста, баннер "Ждём сопряжения", цветные `CircleAvatar`).

### Хранение: как язык — на уровне устройства

`AppSettingsStore` (уже был для языка, ADR 0027) получил
`themeMode()`/`setThemeMode()` — тот же `settings.json`, тот же принцип
(общее для всех профилей на устройстве, не часть CRDT-данных профиля).
Прокидка в `AudilocApp`/`profile_session.dart`/`providers.dart` —
дословно тот же паттерн, что уже был для языка:
`changeThemeModeProvider`/`currentThemeModeProvider`, `_themeMode` поле
в `_AudilocAppState`, `_changeThemeMode` метод, `themeMode: _themeMode`
вместо было зашитого `ThemeMode.dark` во всех четырёх `MaterialApp`/
`MaterialApp.router` конструкторах в `build()`.

### Настройки — новый экран, вход через шестерёнку

`SettingsScreen` (`lib/features/settings/settings_screen.dart`) —
список из: тема (пикер с диалогом), язык (тот же пикер, что раньше жил
в "О приложении" — код переехал один в один), "О приложении" (просто
навигация), "Стереть все данные" (см. ниже). Вход — иконка ⚙️ на
вкладке "Устройства", заменившая там иконку ℹ️ ("О приложении" теперь
на второй уровень).

### "Стереть все данные" — двойная защита + честный сброс состояния

Двухшаговое подтверждение, не одно: первый диалог — предупреждение
(что именно будет стёрто — **все** профили на устройстве, не только
активный), второй — подтверждение вводом фиксированного слова
("УДАЛИТЬ"/"DELETE", т.к. единственного релевантного "имени" тут нет,
в отличие от удаления одного профиля из ADR 0018, где вводится имя
профиля). Тот же принцип "нельзя случайным двойным тапом", что уже был
в `ProfileSwitcherSheet._deleteDialog`.

Сама операция (`AudilocApp._eraseAllData`, вызывается только оттуда —
`eraseAllDataProvider`, тот же паттерн внешнего колбэка, что
`changeLanguageProvider`/`switchProfileProvider`) — не просто удаление
директории: `ProfileSessionHandle.close()` **сначала** (иначе SQLite-файл
профиля ещё открыт процессом — удаление стало бы ненадёжным, в худшем
случае повредило бы файл), затем `eraseDirectoryBestEffort` на **всём**
`appSupportDir` целиком (не только `profiles/` — там же
`profiles.json`, `settings.json`, легаси `audiloc.db` от миграции), затем
сброс каждого поля `_AudilocAppState` в точности к тому же состоянию,
что и в конструкторе, и повторный вызов `_bootstrap()` — то есть
приложение проходит **тот же код**, что настоящий первый запуск
(`needsInitialSetup()` снова `true`, язык снова не выбран → снова
`LanguageChoiceScreen`), а не какую-то отдельную "после-стирания" ветку,
которая могла бы с этим кодом разойтись со временем.

`eraseDirectoryBestEffort` — вынесенная в `lib/data/directory_erase.dart`
копия того, что раньше было приватным `ProfilesStore._eraseDirectory`
(один локнутый файл не должен обрывать удаление всего дерева) — теперь
общая для удаления одного профиля (ADR 0018) и удаления всего
`appSupportDir` целиком, вместо двух копий одной и той же логики.

Отдельная ловушка, которую стоит записать: `AudioService.init()`
(`audio_service` — уведомление/лок-скрин на Android) внутри содержит
`assert(_cacheManager == null)` — вызов дважды за один процесс бросает
assertion error в debug-сборках. `_bootstrap()` раньше предполагался
вызываемым максимум один раз за жизнь процесса; "Стереть все данные"
делает его потенциально повторным — добавлен флаг
`_audioServiceInitialized`, который не сбрасывается стиранием (в
отличие от всего остального состояния) и гарантирует, что
`AudioService.init` реально вызывается не больше одного раза за
процесс, даже когда `_bootstrap()` вызывается снова.

### "О приложении" — чисто информационный

Пикер языка убран (переехал в Настройки). Добавлены: краткое описание
(`aboutDescription`, то же по смыслу, что в README) и кнопка-ссылка на
GitHub-репозиторий (`url_launcher`, `LaunchMode.externalApplication`) —
автор, версия и лицензия там уже были.

## Файлы

Новые: `lib/core/theme/app_colors.dart`,
`lib/features/settings/settings_screen.dart`,
`lib/data/directory_erase.dart`.

Изменены: `lib/core/theme/app_theme.dart` (light+dark вместо только
dark), `lib/data/settings/app_settings_store.dart` (+themeMode),
`lib/data/profiles/profiles_store.dart` (использует
`eraseDirectoryBestEffort` вместо своей копии), `lib/app.dart`,
`lib/core/providers.dart`, `lib/core/profile_session.dart`,
`lib/features/about/about_screen.dart`, `lib/features/devices/devices_screen.dart`
(шестерёнка вместо ℹ️), и ~19 файлов в `lib/features/**` — замена
`AppTheme.*` на `context.colors.*`. `pubspec.yaml`: `url_launcher`.

## Верификация

1. `flutter analyze` — 0 ошибок, 0 предупреждений.
2. `flutter test test/unit/` — все 120 тестов проходят.
3. `flutter test test/widget/mini_player_test.dart` +
   `initial_profile_name_screen_test.dart` — проходят (потребовали
   `theme: AppTheme.dark()` в тестовых `MaterialApp` — без него
   `context.colors` падает на `Theme.of(context).extension<AppColors>()`,
   возвращающем `null`, поскольку тестовый `MaterialApp` без явной темы
   не регистрирует `AppColors` вообще).
   `track_tile_test.dart`/`library_screen_test.dart` упираются в уже
   задокументированное окружение-специфичное зависание shutdown после
   реальных `sqflite_common_ffi`-записей (см. docs/testing-notes.md) —
   то же самое поведение, что и до этого ADR, не регрессия.
4. `flutter build linux` — собирается и реально запускается.
5. Живая проверка переключения тема/язык, "Стереть все данные" (в т.ч.
   что приложение действительно возвращается к первому запуску) — за
   пользователем.
