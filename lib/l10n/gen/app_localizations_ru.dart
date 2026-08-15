// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get commonCancel => 'Отмена';

  @override
  String get commonSave => 'Сохранить';

  @override
  String get commonCreate => 'Создать';

  @override
  String get commonBack => 'Назад';

  @override
  String get commonRetry => 'Повторить';

  @override
  String get commonDelete => 'Удалить';

  @override
  String commonErrorPrefix(Object error) {
    return 'Ошибка: $error';
  }

  @override
  String get fieldName => 'Название';

  @override
  String get commonDecline => 'Отклонить';

  @override
  String get commonAllow => 'Разрешить';

  @override
  String resumePlaybackBody(String trackTitle, String time, String device) {
    return 'Хотите продолжить с «$trackTitle», $time, $device?';
  }

  @override
  String get resumePlaybackContinue => 'Продолжить';

  @override
  String get settingsPlayback => 'Воспроизведение';

  @override
  String get settingsKeyboardShortcuts => 'Управление с клавиатуры';

  @override
  String get settingsKeyboardShortcutsSubtitle =>
      'Пробел — пауза, стрелки — перемотка, медиаклавиши';

  @override
  String get settingsSeekStep => 'Шаг перемотки';

  @override
  String settingsSeekStepSeconds(int seconds) {
    return '$seconds с';
  }

  @override
  String get searchHint => 'Название, исполнитель, альбом…';

  @override
  String get searchStartTyping => 'Начните вводить запрос';

  @override
  String get searchNothingFound => 'Ничего не найдено';

  @override
  String get pairingRequestTitle => 'Запрос на сопряжение';

  @override
  String pairingRequestSameProfile(String name) {
    return '«$name» хочет синхронизироваться с этим устройством.';
  }

  @override
  String pairingRequestDifferentProfile(String name) {
    return '«$name» хочет добавить это устройство в свой профиль. Если вы согласитесь, это устройство переключится на профиль «$name» и загрузит его библиотеку — ваш текущий профиль никуда не денется, вернуться к нему можно через переключатель профилей.';
  }

  @override
  String get shareOfferTitle => 'Поделились треком';

  @override
  String shareOfferSingleTrack(String name) {
    return '«$name» хочет поделиться этим треком.';
  }

  @override
  String shareOfferAlbum(String name, String album, int count) {
    return '«$name» хочет поделиться альбомом «$album» ($count шт.).';
  }

  @override
  String shareOfferTracks(String name, int count) {
    return '«$name» хочет поделиться треками ($count шт.).';
  }

  @override
  String get shareOfferAccept => 'Принять';

  @override
  String get favoritesTitle => 'Избранное';

  @override
  String get favoritesEmptyTitle => 'Пока нет избранных треков';

  @override
  String get favoritesEmptyBody =>
      'Нажмите на сердечко у трека — он появится здесь';

  @override
  String get trashTitle => 'Удалённые';

  @override
  String get trashEmpty => 'Удалённых треков нет';

  @override
  String get trashRestoreTooltip => 'Вернуть в библиотеку';

  @override
  String get trashEraseForeverTooltip => 'Стереть навсегда';

  @override
  String get trashEraseConfirmTitle => 'Стереть навсегда?';

  @override
  String trashEraseConfirmBody(String title) {
    return '«$title» будет удалён с диска на этом устройстве и исчезнет из «Удалённых». Импортировать его снова можно будет только заново, вручную.';
  }

  @override
  String get trashEraseConfirmButton => 'Стереть';

  @override
  String trashErasedSnackbar(String title) {
    return '«$title» стёрт с этого устройства';
  }

  @override
  String get playlistCreateTitle => 'Новый плейлист';

  @override
  String get playlistFallbackName => 'Плейлист';

  @override
  String get playlistEmptyTracks => 'В плейлисте пока нет треков';

  @override
  String get playlistSearchHint => 'Поиск трека';

  @override
  String get playlistAllTracksAdded => 'Все треки уже в плейлисте';

  @override
  String get playlistNothingFound => 'Ничего не найдено';

  @override
  String get playlistAddButton => 'Добавить';

  @override
  String playlistAddButtonWithCount(int count) {
    return 'Добавить ($count)';
  }

  @override
  String get playlistActionRename => 'Переименовать';

  @override
  String get playlistActionPickCover => 'Выбрать обложку';

  @override
  String get playlistRenameTitle => 'Переименовать плейлист';

  @override
  String get playlistDeleteConfirmTitle => 'Удалить плейлист?';

  @override
  String playlistDeleteConfirmBody(String name) {
    return '«$name» будет удалён. Сами треки в библиотеке останутся нетронутыми.';
  }

  @override
  String get playlistCoverFromFile => 'Картинка из файла';

  @override
  String get playlistCoverPickDialogTitle => 'Выберите обложку плейлиста';

  @override
  String get playerNowPlayingTitle => 'Сейчас играет';

  @override
  String get playerNothingPlaying => 'Ничего не воспроизводится';

  @override
  String get playerSourceLibrary => 'Играет: Библиотека';

  @override
  String get playerSourceFavorites => 'Играет: Избранное';

  @override
  String playerSourcePlaylist(String name) {
    return 'Играет: Плейлист «$name»';
  }

  @override
  String get trackActionEdit => 'Редактировать';

  @override
  String get trackActionAddToPlaylist => 'Добавить в плейлист';

  @override
  String get trackActionShare => 'Поделиться';

  @override
  String get trackFileNotDownloadedYet =>
      'Файл ещё не загружен на это устройство';

  @override
  String get trackDeleteConfirmTitle => 'Удалить трек из библиотеки?';

  @override
  String trackDeleteConfirmBody(String title) {
    return '«$title» пропадёт из библиотеки на этом устройстве. Сам файл не удаляется — трек можно вернуть на вкладке «Удалённые».';
  }

  @override
  String trackDeletedSnackbar(String title) {
    return '«$title» удалён из библиотеки';
  }

  @override
  String get trackEditTitle => 'Редактировать трек';

  @override
  String get trackEditPickCoverDialogTitle => 'Выберите обложку';

  @override
  String get fieldTitle => 'Название';

  @override
  String get fieldArtist => 'Исполнитель';

  @override
  String get fieldAlbum => 'Альбом';

  @override
  String get fieldGenre => 'Жанр';

  @override
  String get shareWholeAlbum => 'Поделиться всем альбомом';

  @override
  String get nearbyDevicesLabel => 'Устройства поблизости';

  @override
  String get noNearbyDevices => 'Поблизости не найдено ни одного устройства';

  @override
  String shareSentSnackbar(String name) {
    return 'Отправлено «$name»';
  }

  @override
  String get noPlaylistsYet =>
      'Нет ни одного плейлиста — создайте его на вкладке «Плейлисты»';

  @override
  String addedToPlaylistSnackbar(String name) {
    return 'Добавлено в «$name»';
  }

  @override
  String get navLibrary => 'Библиотека';

  @override
  String get navPlaylists => 'Плейлисты';

  @override
  String get navSearch => 'Поиск';

  @override
  String get navDevices => 'Устройства';

  @override
  String get libraryAddTrackTooltip => 'Добавить трек';

  @override
  String get libraryAddFolderTooltip => 'Добавить папку';

  @override
  String libraryLoadError(Object error) {
    return 'Ошибка загрузки библиотеки: $error';
  }

  @override
  String get libraryPickFolderDialogTitle => 'Выберите папку с музыкой';

  @override
  String get libraryImportStarted => 'Импорт запущен…';

  @override
  String libraryImportResult(int imported, int duplicates, int failed) {
    return 'Добавлено: $imported, пропущено дублей: $duplicates, ошибок: $failed';
  }

  @override
  String get libraryPickFilesDialogTitle => 'Выберите треки';

  @override
  String get librarySortTitle => 'Название';

  @override
  String get librarySortArtist => 'Исполнитель';

  @override
  String get librarySortAddedAt => 'Дата добавления';

  @override
  String get librarySortTooltip => 'Сортировка';

  @override
  String get libraryEmptyTitle => 'Библиотека пуста';

  @override
  String get libraryEmptyBody =>
      'Импортируйте папку с музыкой — теги и обложки подтянутся автоматически';

  @override
  String get libraryPickFolderButton => 'Выбрать папку';

  @override
  String get trackDownloadingIndeterminate => 'загрузка…';

  @override
  String trackDownloadingPercent(int percent) {
    return 'загрузка $percent%';
  }

  @override
  String get trackWaitingForTransfer => 'ждёт передачи с другого устройства';

  @override
  String get startupErrorTitle => 'Не удалось запустить AudiLoc';

  @override
  String get pairingBannerText =>
      'Ждём сопряжения со вторым устройством — подтвердите на вкладке «Устройства»';

  @override
  String get onboardingWelcomeTitle => 'Добро пожаловать в AudiLoc';

  @override
  String get onboardingWelcomeSubtitle =>
      'Это устройство уже используете вы сами где-то ещё, или это первый раз, когда вы открываете AudiLoc?';

  @override
  String get onboardingNewProfileButton => 'Здесь я впервые — новый профиль';

  @override
  String get onboardingSecondDeviceButton =>
      'Это моё второе устройство — сопрячь с первым';

  @override
  String get onboardingNameTitle => 'Как вас зовут?';

  @override
  String get onboardingNameSubtitle =>
      'Это имя вашего профиля — у него будет своя библиотека и свой список сопряжённых устройств. Позже на этом же устройстве можно добавить другие профили для других людей.';

  @override
  String get onboardingNameHint => 'Имя профиля';

  @override
  String get onboardingStartButton => 'Начать';

  @override
  String get profilesTitle => 'Профили';

  @override
  String get profilesSubtitle =>
      'У каждого профиля своя библиотека и свой список сопряжённых устройств. Долгий тап — переименовать, значок корзины — удалить безвозвратно.';

  @override
  String get profileDeleteTooltip => 'Удалить профиль';

  @override
  String get profilesNewProfile => 'Новый профиль';

  @override
  String get profilesWaitForPairingTitle =>
      'Это моё второе устройство — ждать сопряжения';

  @override
  String get profilesWaitForPairingSubtitle =>
      'Вместо пустого профиля — дождаться сопряжения с другим вашим устройством и стать его копией';

  @override
  String get profileCreateNameHint => 'Имя';

  @override
  String get profileRenameTitle => 'Переименовать профиль';

  @override
  String get profileDeleteTitle => 'Удалить профиль?';

  @override
  String profileDeleteBody(String name) {
    return '«$name» и вся его библиотека — треки, плейлисты, обложки, список сопряжённых устройств — будут удалены безвозвратно. Отменить это будет нельзя.';
  }

  @override
  String profileDeleteConfirmPrompt(String name) {
    return 'Чтобы подтвердить, введите «$name»:';
  }

  @override
  String get profileDeleteConfirmButton => 'Удалить безвозвратно';

  @override
  String profileDeletePartialError(Object error) {
    return 'Профиль удалён из списка, но часть файлов стереть не удалось: $error';
  }

  @override
  String devicesProfileLabel(String name) {
    return 'Профиль: $name';
  }

  @override
  String get devicesProfileSubtitle =>
      'У каждого профиля своя библиотека и свои устройства';

  @override
  String get devicesChangeProfile => 'Сменить';

  @override
  String get devicesKnownDevicesLabel => 'Известные устройства';

  @override
  String get devicesNoneFound =>
      'Пока не найдено ни одного устройства в локальной сети';

  @override
  String devicesErrorPrefix(Object error) {
    return 'Ошибка: $error';
  }

  @override
  String get devicesRefreshTooltip => 'Обновить список устройств';

  @override
  String get devicesNearbyLabel => 'Найдено рядом';

  @override
  String get devicesUnpaired => 'Не сопряжено';

  @override
  String get devicesAddPeer => 'Добавить';

  @override
  String devicesPairingRequestSent(String name) {
    return 'Запрос на сопряжение отправлен «$name»';
  }

  @override
  String get devicesFileTransferTitle => 'Передача файлов';

  @override
  String get devicesAllFilesPresent =>
      'Все известные треки уже есть на этом устройстве';

  @override
  String devicesQueuedCount(int count) {
    return 'В очереди: $count — появятся сами, как только в сети найдётся устройство с этими файлами';
  }

  @override
  String syncBadgeMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Синхронизировано $count изменения',
      many: 'Синхронизировано $count изменений',
      few: 'Синхронизировано $count изменения',
      one: 'Синхронизировано $count изменение',
    );
    return '$_temp0';
  }

  @override
  String get deviceOnline => 'В сети';

  @override
  String get deviceOffline => 'Не в сети';

  @override
  String deviceLastSeen(String relative) {
    return 'Не в сети · был(а) в сети $relative';
  }

  @override
  String get deviceLastSeenJustNow => 'только что';

  @override
  String deviceLastSeenMinutes(int count) {
    return '$count мин назад';
  }

  @override
  String deviceLastSeenHours(int count) {
    return '$count ч назад';
  }

  @override
  String deviceLastSeenDays(int count) {
    return '$count дн назад';
  }

  @override
  String get deviceSyncNowTooltip => 'Синхронизировать сейчас';

  @override
  String get deviceUnpairTooltip => 'Отвязать устройство';

  @override
  String get deviceUnpairTitle => 'Отвязать устройство?';

  @override
  String deviceUnpairBody(String name) {
    return '«$name» перестанет синхронизироваться с этим устройством. Чтобы связать их снова, потребуется новое подтверждение с обеих сторон.';
  }

  @override
  String get deviceUnpairConfirm => 'Отвязать';

  @override
  String get aboutTitle => 'О приложении';

  @override
  String get aboutAuthor => 'Автор: zaigard';

  @override
  String get aboutLicense =>
      'Лицензия: PolyForm Noncommercial 1.0.0 — свободно для любых некоммерческих целей; коммерческое использование — по отдельному разрешению автора.';

  @override
  String get aboutHowToUse => 'Как пользоваться';

  @override
  String get aboutGuideLibraryTitle => 'Библиотека';

  @override
  String get aboutGuideLibraryBody =>
      'Импортируйте папку или отдельные файлы — теги и обложки подтянутся автоматически, повторный импорт того же файла не создаёт дубль. Долгий тап по треку (на десктопе — правый клик) открывает меню: редактировать (название/исполнитель/альбом/жанр/обложку), добавить в плейлист, поделиться, удалить. Удаление — не безвозвратное: трек попадает в «Удалённые» (вкладка «Плейлисты»), откуда его можно вернуть или стереть по-настоящему.';

  @override
  String get aboutGuidePlaylistsTitle => 'Плейлисты';

  @override
  String get aboutGuidePlaylistsBody =>
      'Кнопка «+» создаёт новый плейлист. Внутри плейлиста кнопка добавления треков открывает поиск с множественным выбором — можно отметить сразу несколько и добавить их одной кнопкой. Долгий тап (правый клик) по плейлисту в сетке — переименовать, удалить или выбрать обложку (одну из обложек его же треков или картинку из файла). «Избранное» и «Удалённые» — отдельные встроенные карточки в той же сетке.';

  @override
  String get aboutGuideDevicesTitle => 'Устройства и сопряжение';

  @override
  String get aboutGuideDevicesBody =>
      'Устройства поблизости в локальной сети видны сами, без настройки — на вкладке «Устройства» под заголовком «Найдено рядом». «Добавить» отправляет запрос на сопряжение; на другом устройстве нужно подтвердить его («Разрешить»). Сопряжение работает только внутри одного и того же профиля — если нужно передать что-то в другой профиль (в том числе чужой), используйте «Поделиться» вместо сопряжения.';

  @override
  String get aboutGuideShareTitle => '«Поделиться»';

  @override
  String get aboutGuideShareBody =>
      'В меню трека пункт «Поделиться» отправляет этот трек (или, по желанию, весь его альбом) любому видимому поблизости устройству — даже не сопряжённому и с другим профилем. Принимающая сторона видит название и обложку и сама решает, принять ли — просто скачивается и добавляется в библиотеку, без слияния профилей.';

  @override
  String get aboutGuideProfilesTitle => 'Профили';

  @override
  String get aboutGuideProfilesBody =>
      'Несколько человек могут делить одно устройство — у каждого своя библиотека и свой список сопряжённых устройств; переключение — карточка профиля на вкладке «Устройства» → «Сменить». Если это, наоборот, второе устройство одного и того же человека — кнопка «Ждать сопряжения» (при создании профиля или из переключателя) делает его копией уже существующего. Удаление профиля необратимо и требует ввода его имени для подтверждения; удалить можно только неактивный профиль.';

  @override
  String aboutVersion(String version) {
    return 'Версия $version';
  }

  @override
  String get aboutDescription =>
      'AudiLoc — P2P музыкальный плеер с автосинхронизацией библиотеки в локальной сети, без облака и без центрального сервера.';

  @override
  String get aboutGithubLink => 'Исходный код на GitHub';

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get settingsTheme => 'Тема';

  @override
  String get settingsThemeSystem => 'Как в системе';

  @override
  String get settingsThemeLight => 'Светлая';

  @override
  String get settingsThemeDark => 'Тёмная';

  @override
  String get settingsLanguage => 'Язык';

  @override
  String get settingsLanguageSystem => 'Как в системе';

  @override
  String get settingsAbout => 'О приложении';

  @override
  String get settingsEraseData => 'Стереть все данные';

  @override
  String get settingsEraseDataSubtitle =>
      'Удаляет все профили и настройки — приложение станет как только что установленное';

  @override
  String get settingsEraseDataWarningTitle => 'Стереть все данные?';

  @override
  String get settingsEraseDataWarningBody =>
      'Будут безвозвратно удалены все профили на этом устройстве — вся библиотека, плейлисты, обложки, список сопряжённых устройств у каждого из них — и настройки языка/темы. Это затрагивает все профили, не только текущий. Отменить это будет нельзя.';

  @override
  String get settingsEraseDataWarningContinue => 'Продолжить';

  @override
  String get settingsEraseDataFinalTitle => 'Последнее подтверждение';

  @override
  String settingsEraseDataFinalBody(String keyword) {
    return 'Чтобы подтвердить, введите «$keyword»:';
  }

  @override
  String get settingsEraseDataFinalKeyword => 'УДАЛИТЬ';

  @override
  String get settingsEraseDataFinalButton => 'Стереть всё безвозвратно';
}
