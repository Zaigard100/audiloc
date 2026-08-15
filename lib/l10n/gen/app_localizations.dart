import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
  ];

  /// No description provided for @commonCancel.
  ///
  /// In ru, this message translates to:
  /// **'Отмена'**
  String get commonCancel;

  /// No description provided for @commonSave.
  ///
  /// In ru, this message translates to:
  /// **'Сохранить'**
  String get commonSave;

  /// No description provided for @commonCreate.
  ///
  /// In ru, this message translates to:
  /// **'Создать'**
  String get commonCreate;

  /// No description provided for @commonBack.
  ///
  /// In ru, this message translates to:
  /// **'Назад'**
  String get commonBack;

  /// No description provided for @commonRetry.
  ///
  /// In ru, this message translates to:
  /// **'Повторить'**
  String get commonRetry;

  /// No description provided for @commonDelete.
  ///
  /// In ru, this message translates to:
  /// **'Удалить'**
  String get commonDelete;

  /// No description provided for @commonErrorPrefix.
  ///
  /// In ru, this message translates to:
  /// **'Ошибка: {error}'**
  String commonErrorPrefix(Object error);

  /// No description provided for @fieldName.
  ///
  /// In ru, this message translates to:
  /// **'Название'**
  String get fieldName;

  /// No description provided for @commonDecline.
  ///
  /// In ru, this message translates to:
  /// **'Отклонить'**
  String get commonDecline;

  /// No description provided for @commonAllow.
  ///
  /// In ru, this message translates to:
  /// **'Разрешить'**
  String get commonAllow;

  /// No description provided for @commonNo.
  ///
  /// In ru, this message translates to:
  /// **'Нет'**
  String get commonNo;

  /// No description provided for @resumePlaybackTitle.
  ///
  /// In ru, this message translates to:
  /// **'Продолжить воспроизведение?'**
  String get resumePlaybackTitle;

  /// No description provided for @resumePlaybackBody.
  ///
  /// In ru, this message translates to:
  /// **'Хотите продолжить с «{trackTitle}», {time}, {device}?'**
  String resumePlaybackBody(String trackTitle, String time, String device);

  /// No description provided for @resumePlaybackContinue.
  ///
  /// In ru, this message translates to:
  /// **'Продолжить'**
  String get resumePlaybackContinue;

  /// No description provided for @settingsPlayback.
  ///
  /// In ru, this message translates to:
  /// **'Воспроизведение'**
  String get settingsPlayback;

  /// No description provided for @settingsKeyboardShortcuts.
  ///
  /// In ru, this message translates to:
  /// **'Управление с клавиатуры'**
  String get settingsKeyboardShortcuts;

  /// No description provided for @settingsKeyboardShortcutsSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Пробел — пауза, стрелки — перемотка, медиаклавиши'**
  String get settingsKeyboardShortcutsSubtitle;

  /// No description provided for @settingsSeekStep.
  ///
  /// In ru, this message translates to:
  /// **'Шаг перемотки'**
  String get settingsSeekStep;

  /// No description provided for @settingsSeekStepSeconds.
  ///
  /// In ru, this message translates to:
  /// **'{seconds} с'**
  String settingsSeekStepSeconds(int seconds);

  /// No description provided for @searchHint.
  ///
  /// In ru, this message translates to:
  /// **'Название, исполнитель, альбом…'**
  String get searchHint;

  /// No description provided for @searchStartTyping.
  ///
  /// In ru, this message translates to:
  /// **'Начните вводить запрос'**
  String get searchStartTyping;

  /// No description provided for @searchNothingFound.
  ///
  /// In ru, this message translates to:
  /// **'Ничего не найдено'**
  String get searchNothingFound;

  /// No description provided for @pairingRequestTitle.
  ///
  /// In ru, this message translates to:
  /// **'Запрос на сопряжение'**
  String get pairingRequestTitle;

  /// No description provided for @pairingRequestSameProfile.
  ///
  /// In ru, this message translates to:
  /// **'«{name}» хочет синхронизироваться с этим устройством.'**
  String pairingRequestSameProfile(String name);

  /// No description provided for @pairingRequestDifferentProfile.
  ///
  /// In ru, this message translates to:
  /// **'«{name}» хочет добавить это устройство в свой профиль. Если вы согласитесь, это устройство переключится на профиль «{name}» и загрузит его библиотеку — ваш текущий профиль никуда не денется, вернуться к нему можно через переключатель профилей.'**
  String pairingRequestDifferentProfile(String name);

  /// No description provided for @shareOfferTitle.
  ///
  /// In ru, this message translates to:
  /// **'Поделились треком'**
  String get shareOfferTitle;

  /// No description provided for @shareOfferSingleTrack.
  ///
  /// In ru, this message translates to:
  /// **'«{name}» хочет поделиться этим треком.'**
  String shareOfferSingleTrack(String name);

  /// No description provided for @shareOfferAlbum.
  ///
  /// In ru, this message translates to:
  /// **'«{name}» хочет поделиться альбомом «{album}» ({count} шт.).'**
  String shareOfferAlbum(String name, String album, int count);

  /// No description provided for @shareOfferTracks.
  ///
  /// In ru, this message translates to:
  /// **'«{name}» хочет поделиться треками ({count} шт.).'**
  String shareOfferTracks(String name, int count);

  /// No description provided for @shareOfferAccept.
  ///
  /// In ru, this message translates to:
  /// **'Принять'**
  String get shareOfferAccept;

  /// No description provided for @favoritesTitle.
  ///
  /// In ru, this message translates to:
  /// **'Избранное'**
  String get favoritesTitle;

  /// No description provided for @favoritesEmptyTitle.
  ///
  /// In ru, this message translates to:
  /// **'Пока нет избранных треков'**
  String get favoritesEmptyTitle;

  /// No description provided for @favoritesEmptyBody.
  ///
  /// In ru, this message translates to:
  /// **'Нажмите на сердечко у трека — он появится здесь'**
  String get favoritesEmptyBody;

  /// No description provided for @trashTitle.
  ///
  /// In ru, this message translates to:
  /// **'Удалённые'**
  String get trashTitle;

  /// No description provided for @trashEmpty.
  ///
  /// In ru, this message translates to:
  /// **'Удалённых треков нет'**
  String get trashEmpty;

  /// No description provided for @trashRestoreTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Вернуть в библиотеку'**
  String get trashRestoreTooltip;

  /// No description provided for @trashEraseForeverTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Стереть навсегда'**
  String get trashEraseForeverTooltip;

  /// No description provided for @trashEraseConfirmTitle.
  ///
  /// In ru, this message translates to:
  /// **'Стереть навсегда?'**
  String get trashEraseConfirmTitle;

  /// No description provided for @trashEraseConfirmBody.
  ///
  /// In ru, this message translates to:
  /// **'«{title}» будет удалён с диска на этом устройстве и исчезнет из «Удалённых». Импортировать его снова можно будет только заново, вручную.'**
  String trashEraseConfirmBody(String title);

  /// No description provided for @trashEraseConfirmButton.
  ///
  /// In ru, this message translates to:
  /// **'Стереть'**
  String get trashEraseConfirmButton;

  /// No description provided for @trashErasedSnackbar.
  ///
  /// In ru, this message translates to:
  /// **'«{title}» стёрт с этого устройства'**
  String trashErasedSnackbar(String title);

  /// No description provided for @playlistCreateTitle.
  ///
  /// In ru, this message translates to:
  /// **'Новый плейлист'**
  String get playlistCreateTitle;

  /// No description provided for @playlistFallbackName.
  ///
  /// In ru, this message translates to:
  /// **'Плейлист'**
  String get playlistFallbackName;

  /// No description provided for @playlistEmptyTracks.
  ///
  /// In ru, this message translates to:
  /// **'В плейлисте пока нет треков'**
  String get playlistEmptyTracks;

  /// No description provided for @playlistSearchHint.
  ///
  /// In ru, this message translates to:
  /// **'Поиск трека'**
  String get playlistSearchHint;

  /// No description provided for @playlistAllTracksAdded.
  ///
  /// In ru, this message translates to:
  /// **'Все треки уже в плейлисте'**
  String get playlistAllTracksAdded;

  /// No description provided for @playlistNothingFound.
  ///
  /// In ru, this message translates to:
  /// **'Ничего не найдено'**
  String get playlistNothingFound;

  /// No description provided for @playlistAddButton.
  ///
  /// In ru, this message translates to:
  /// **'Добавить'**
  String get playlistAddButton;

  /// No description provided for @playlistAddButtonWithCount.
  ///
  /// In ru, this message translates to:
  /// **'Добавить ({count})'**
  String playlistAddButtonWithCount(int count);

  /// No description provided for @playlistActionRename.
  ///
  /// In ru, this message translates to:
  /// **'Переименовать'**
  String get playlistActionRename;

  /// No description provided for @playlistActionPickCover.
  ///
  /// In ru, this message translates to:
  /// **'Выбрать обложку'**
  String get playlistActionPickCover;

  /// No description provided for @playlistRenameTitle.
  ///
  /// In ru, this message translates to:
  /// **'Переименовать плейлист'**
  String get playlistRenameTitle;

  /// No description provided for @playlistDeleteConfirmTitle.
  ///
  /// In ru, this message translates to:
  /// **'Удалить плейлист?'**
  String get playlistDeleteConfirmTitle;

  /// No description provided for @playlistDeleteConfirmBody.
  ///
  /// In ru, this message translates to:
  /// **'«{name}» будет удалён. Сами треки в библиотеке останутся нетронутыми.'**
  String playlistDeleteConfirmBody(String name);

  /// No description provided for @playlistCoverFromFile.
  ///
  /// In ru, this message translates to:
  /// **'Картинка из файла'**
  String get playlistCoverFromFile;

  /// No description provided for @playlistCoverPickDialogTitle.
  ///
  /// In ru, this message translates to:
  /// **'Выберите обложку плейлиста'**
  String get playlistCoverPickDialogTitle;

  /// No description provided for @playerNowPlayingTitle.
  ///
  /// In ru, this message translates to:
  /// **'Сейчас играет'**
  String get playerNowPlayingTitle;

  /// No description provided for @playerNothingPlaying.
  ///
  /// In ru, this message translates to:
  /// **'Ничего не воспроизводится'**
  String get playerNothingPlaying;

  /// No description provided for @playerSourceLibrary.
  ///
  /// In ru, this message translates to:
  /// **'Играет: Библиотека'**
  String get playerSourceLibrary;

  /// No description provided for @playerSourceFavorites.
  ///
  /// In ru, this message translates to:
  /// **'Играет: Избранное'**
  String get playerSourceFavorites;

  /// No description provided for @playerSourcePlaylist.
  ///
  /// In ru, this message translates to:
  /// **'Играет: Плейлист «{name}»'**
  String playerSourcePlaylist(String name);

  /// No description provided for @trackActionEdit.
  ///
  /// In ru, this message translates to:
  /// **'Редактировать'**
  String get trackActionEdit;

  /// No description provided for @trackActionAddToPlaylist.
  ///
  /// In ru, this message translates to:
  /// **'Добавить в плейлист'**
  String get trackActionAddToPlaylist;

  /// No description provided for @trackActionShare.
  ///
  /// In ru, this message translates to:
  /// **'Поделиться'**
  String get trackActionShare;

  /// No description provided for @trackFileNotDownloadedYet.
  ///
  /// In ru, this message translates to:
  /// **'Файл ещё не загружен на это устройство'**
  String get trackFileNotDownloadedYet;

  /// No description provided for @trackDeleteConfirmTitle.
  ///
  /// In ru, this message translates to:
  /// **'Удалить трек из библиотеки?'**
  String get trackDeleteConfirmTitle;

  /// No description provided for @trackDeleteConfirmBody.
  ///
  /// In ru, this message translates to:
  /// **'«{title}» пропадёт из библиотеки на этом устройстве. Сам файл не удаляется — трек можно вернуть на вкладке «Удалённые».'**
  String trackDeleteConfirmBody(String title);

  /// No description provided for @trackDeletedSnackbar.
  ///
  /// In ru, this message translates to:
  /// **'«{title}» удалён из библиотеки'**
  String trackDeletedSnackbar(String title);

  /// No description provided for @trackEditTitle.
  ///
  /// In ru, this message translates to:
  /// **'Редактировать трек'**
  String get trackEditTitle;

  /// No description provided for @trackEditPickCoverDialogTitle.
  ///
  /// In ru, this message translates to:
  /// **'Выберите обложку'**
  String get trackEditPickCoverDialogTitle;

  /// No description provided for @fieldTitle.
  ///
  /// In ru, this message translates to:
  /// **'Название'**
  String get fieldTitle;

  /// No description provided for @fieldArtist.
  ///
  /// In ru, this message translates to:
  /// **'Исполнитель'**
  String get fieldArtist;

  /// No description provided for @fieldAlbum.
  ///
  /// In ru, this message translates to:
  /// **'Альбом'**
  String get fieldAlbum;

  /// No description provided for @fieldGenre.
  ///
  /// In ru, this message translates to:
  /// **'Жанр'**
  String get fieldGenre;

  /// No description provided for @shareWholeAlbum.
  ///
  /// In ru, this message translates to:
  /// **'Поделиться всем альбомом'**
  String get shareWholeAlbum;

  /// No description provided for @nearbyDevicesLabel.
  ///
  /// In ru, this message translates to:
  /// **'Устройства поблизости'**
  String get nearbyDevicesLabel;

  /// No description provided for @noNearbyDevices.
  ///
  /// In ru, this message translates to:
  /// **'Поблизости не найдено ни одного устройства'**
  String get noNearbyDevices;

  /// No description provided for @shareSentSnackbar.
  ///
  /// In ru, this message translates to:
  /// **'Отправлено «{name}»'**
  String shareSentSnackbar(String name);

  /// No description provided for @noPlaylistsYet.
  ///
  /// In ru, this message translates to:
  /// **'Нет ни одного плейлиста — создайте его на вкладке «Плейлисты»'**
  String get noPlaylistsYet;

  /// No description provided for @addedToPlaylistSnackbar.
  ///
  /// In ru, this message translates to:
  /// **'Добавлено в «{name}»'**
  String addedToPlaylistSnackbar(String name);

  /// No description provided for @navLibrary.
  ///
  /// In ru, this message translates to:
  /// **'Библиотека'**
  String get navLibrary;

  /// No description provided for @navPlaylists.
  ///
  /// In ru, this message translates to:
  /// **'Плейлисты'**
  String get navPlaylists;

  /// No description provided for @navSearch.
  ///
  /// In ru, this message translates to:
  /// **'Поиск'**
  String get navSearch;

  /// No description provided for @navDevices.
  ///
  /// In ru, this message translates to:
  /// **'Устройства'**
  String get navDevices;

  /// No description provided for @libraryAddTrackTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Добавить трек'**
  String get libraryAddTrackTooltip;

  /// No description provided for @libraryAddFolderTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Добавить папку'**
  String get libraryAddFolderTooltip;

  /// No description provided for @libraryLoadError.
  ///
  /// In ru, this message translates to:
  /// **'Ошибка загрузки библиотеки: {error}'**
  String libraryLoadError(Object error);

  /// No description provided for @libraryPickFolderDialogTitle.
  ///
  /// In ru, this message translates to:
  /// **'Выберите папку с музыкой'**
  String get libraryPickFolderDialogTitle;

  /// No description provided for @libraryImportStarted.
  ///
  /// In ru, this message translates to:
  /// **'Импорт запущен…'**
  String get libraryImportStarted;

  /// No description provided for @libraryImportResult.
  ///
  /// In ru, this message translates to:
  /// **'Добавлено: {imported}, пропущено дублей: {duplicates}, ошибок: {failed}'**
  String libraryImportResult(int imported, int duplicates, int failed);

  /// No description provided for @libraryPickFilesDialogTitle.
  ///
  /// In ru, this message translates to:
  /// **'Выберите треки'**
  String get libraryPickFilesDialogTitle;

  /// No description provided for @librarySortTitle.
  ///
  /// In ru, this message translates to:
  /// **'Название'**
  String get librarySortTitle;

  /// No description provided for @librarySortArtist.
  ///
  /// In ru, this message translates to:
  /// **'Исполнитель'**
  String get librarySortArtist;

  /// No description provided for @librarySortAddedAt.
  ///
  /// In ru, this message translates to:
  /// **'Дата добавления'**
  String get librarySortAddedAt;

  /// No description provided for @librarySortTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Сортировка'**
  String get librarySortTooltip;

  /// No description provided for @libraryEmptyTitle.
  ///
  /// In ru, this message translates to:
  /// **'Библиотека пуста'**
  String get libraryEmptyTitle;

  /// No description provided for @libraryEmptyBody.
  ///
  /// In ru, this message translates to:
  /// **'Импортируйте папку с музыкой — теги и обложки подтянутся автоматически'**
  String get libraryEmptyBody;

  /// No description provided for @libraryPickFolderButton.
  ///
  /// In ru, this message translates to:
  /// **'Выбрать папку'**
  String get libraryPickFolderButton;

  /// No description provided for @trackDownloadingIndeterminate.
  ///
  /// In ru, this message translates to:
  /// **'загрузка…'**
  String get trackDownloadingIndeterminate;

  /// No description provided for @trackDownloadingPercent.
  ///
  /// In ru, this message translates to:
  /// **'загрузка {percent}%'**
  String trackDownloadingPercent(int percent);

  /// No description provided for @trackWaitingForTransfer.
  ///
  /// In ru, this message translates to:
  /// **'ждёт передачи с другого устройства'**
  String get trackWaitingForTransfer;

  /// No description provided for @startupErrorTitle.
  ///
  /// In ru, this message translates to:
  /// **'Не удалось запустить AudiLoc'**
  String get startupErrorTitle;

  /// No description provided for @pairingBannerText.
  ///
  /// In ru, this message translates to:
  /// **'Ждём сопряжения со вторым устройством — подтвердите на вкладке «Устройства»'**
  String get pairingBannerText;

  /// No description provided for @onboardingWelcomeTitle.
  ///
  /// In ru, this message translates to:
  /// **'Добро пожаловать в AudiLoc'**
  String get onboardingWelcomeTitle;

  /// No description provided for @onboardingWelcomeSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Это устройство уже используете вы сами где-то ещё, или это первый раз, когда вы открываете AudiLoc?'**
  String get onboardingWelcomeSubtitle;

  /// No description provided for @onboardingNewProfileButton.
  ///
  /// In ru, this message translates to:
  /// **'Здесь я впервые — новый профиль'**
  String get onboardingNewProfileButton;

  /// No description provided for @onboardingSecondDeviceButton.
  ///
  /// In ru, this message translates to:
  /// **'Это моё второе устройство — сопрячь с первым'**
  String get onboardingSecondDeviceButton;

  /// No description provided for @onboardingNameTitle.
  ///
  /// In ru, this message translates to:
  /// **'Как вас зовут?'**
  String get onboardingNameTitle;

  /// No description provided for @onboardingNameSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Это имя вашего профиля — у него будет своя библиотека и свой список сопряжённых устройств. Позже на этом же устройстве можно добавить другие профили для других людей.'**
  String get onboardingNameSubtitle;

  /// No description provided for @onboardingNameHint.
  ///
  /// In ru, this message translates to:
  /// **'Имя профиля'**
  String get onboardingNameHint;

  /// No description provided for @onboardingStartButton.
  ///
  /// In ru, this message translates to:
  /// **'Начать'**
  String get onboardingStartButton;

  /// No description provided for @profilesTitle.
  ///
  /// In ru, this message translates to:
  /// **'Профили'**
  String get profilesTitle;

  /// No description provided for @profilesSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'У каждого профиля своя библиотека и свой список сопряжённых устройств. Долгий тап — переименовать, значок корзины — удалить безвозвратно.'**
  String get profilesSubtitle;

  /// No description provided for @profileDeleteTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Удалить профиль'**
  String get profileDeleteTooltip;

  /// No description provided for @profilesNewProfile.
  ///
  /// In ru, this message translates to:
  /// **'Новый профиль'**
  String get profilesNewProfile;

  /// No description provided for @profilesWaitForPairingTitle.
  ///
  /// In ru, this message translates to:
  /// **'Это моё второе устройство — ждать сопряжения'**
  String get profilesWaitForPairingTitle;

  /// No description provided for @profilesWaitForPairingSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Вместо пустого профиля — дождаться сопряжения с другим вашим устройством и стать его копией'**
  String get profilesWaitForPairingSubtitle;

  /// No description provided for @profileCreateNameHint.
  ///
  /// In ru, this message translates to:
  /// **'Имя'**
  String get profileCreateNameHint;

  /// No description provided for @profileRenameTitle.
  ///
  /// In ru, this message translates to:
  /// **'Переименовать профиль'**
  String get profileRenameTitle;

  /// No description provided for @profileDeleteTitle.
  ///
  /// In ru, this message translates to:
  /// **'Удалить профиль?'**
  String get profileDeleteTitle;

  /// No description provided for @profileDeleteBody.
  ///
  /// In ru, this message translates to:
  /// **'«{name}» и вся его библиотека — треки, плейлисты, обложки, список сопряжённых устройств — будут удалены безвозвратно. Отменить это будет нельзя.'**
  String profileDeleteBody(String name);

  /// No description provided for @profileDeleteConfirmPrompt.
  ///
  /// In ru, this message translates to:
  /// **'Чтобы подтвердить, введите «{name}»:'**
  String profileDeleteConfirmPrompt(String name);

  /// No description provided for @profileDeleteConfirmButton.
  ///
  /// In ru, this message translates to:
  /// **'Удалить безвозвратно'**
  String get profileDeleteConfirmButton;

  /// No description provided for @profileDeletePartialError.
  ///
  /// In ru, this message translates to:
  /// **'Профиль удалён из списка, но часть файлов стереть не удалось: {error}'**
  String profileDeletePartialError(Object error);

  /// No description provided for @devicesProfileLabel.
  ///
  /// In ru, this message translates to:
  /// **'Профиль: {name}'**
  String devicesProfileLabel(String name);

  /// No description provided for @devicesProfileSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'У каждого профиля своя библиотека и свои устройства'**
  String get devicesProfileSubtitle;

  /// No description provided for @devicesChangeProfile.
  ///
  /// In ru, this message translates to:
  /// **'Сменить'**
  String get devicesChangeProfile;

  /// No description provided for @devicesKnownDevicesLabel.
  ///
  /// In ru, this message translates to:
  /// **'Известные устройства'**
  String get devicesKnownDevicesLabel;

  /// No description provided for @devicesNoneFound.
  ///
  /// In ru, this message translates to:
  /// **'Пока не найдено ни одного устройства в локальной сети'**
  String get devicesNoneFound;

  /// No description provided for @devicesErrorPrefix.
  ///
  /// In ru, this message translates to:
  /// **'Ошибка: {error}'**
  String devicesErrorPrefix(Object error);

  /// No description provided for @devicesRefreshTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Обновить список устройств'**
  String get devicesRefreshTooltip;

  /// No description provided for @devicesNearbyLabel.
  ///
  /// In ru, this message translates to:
  /// **'Найдено рядом'**
  String get devicesNearbyLabel;

  /// No description provided for @devicesUnpaired.
  ///
  /// In ru, this message translates to:
  /// **'Не сопряжено'**
  String get devicesUnpaired;

  /// No description provided for @devicesAddPeer.
  ///
  /// In ru, this message translates to:
  /// **'Добавить'**
  String get devicesAddPeer;

  /// No description provided for @devicesPairingRequestSent.
  ///
  /// In ru, this message translates to:
  /// **'Запрос на сопряжение отправлен «{name}»'**
  String devicesPairingRequestSent(String name);

  /// No description provided for @devicesFileTransferTitle.
  ///
  /// In ru, this message translates to:
  /// **'Передача файлов'**
  String get devicesFileTransferTitle;

  /// No description provided for @devicesAllFilesPresent.
  ///
  /// In ru, this message translates to:
  /// **'Все известные треки уже есть на этом устройстве'**
  String get devicesAllFilesPresent;

  /// No description provided for @devicesQueuedCount.
  ///
  /// In ru, this message translates to:
  /// **'В очереди: {count} — появятся сами, как только в сети найдётся устройство с этими файлами'**
  String devicesQueuedCount(int count);

  /// No description provided for @syncBadgeMessage.
  ///
  /// In ru, this message translates to:
  /// **'{count, plural, one{Синхронизировано {count} изменение} few{Синхронизировано {count} изменения} many{Синхронизировано {count} изменений} other{Синхронизировано {count} изменения}}'**
  String syncBadgeMessage(int count);

  /// No description provided for @deviceOnline.
  ///
  /// In ru, this message translates to:
  /// **'В сети'**
  String get deviceOnline;

  /// No description provided for @deviceOffline.
  ///
  /// In ru, this message translates to:
  /// **'Не в сети'**
  String get deviceOffline;

  /// No description provided for @deviceLastSeen.
  ///
  /// In ru, this message translates to:
  /// **'Не в сети · был(а) в сети {relative}'**
  String deviceLastSeen(String relative);

  /// No description provided for @deviceLastSeenJustNow.
  ///
  /// In ru, this message translates to:
  /// **'только что'**
  String get deviceLastSeenJustNow;

  /// No description provided for @deviceLastSeenMinutes.
  ///
  /// In ru, this message translates to:
  /// **'{count} мин назад'**
  String deviceLastSeenMinutes(int count);

  /// No description provided for @deviceLastSeenHours.
  ///
  /// In ru, this message translates to:
  /// **'{count} ч назад'**
  String deviceLastSeenHours(int count);

  /// No description provided for @deviceLastSeenDays.
  ///
  /// In ru, this message translates to:
  /// **'{count} дн назад'**
  String deviceLastSeenDays(int count);

  /// No description provided for @deviceSyncNowTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Синхронизировать сейчас'**
  String get deviceSyncNowTooltip;

  /// No description provided for @deviceUnpairTooltip.
  ///
  /// In ru, this message translates to:
  /// **'Отвязать устройство'**
  String get deviceUnpairTooltip;

  /// No description provided for @deviceUnpairTitle.
  ///
  /// In ru, this message translates to:
  /// **'Отвязать устройство?'**
  String get deviceUnpairTitle;

  /// No description provided for @deviceUnpairBody.
  ///
  /// In ru, this message translates to:
  /// **'«{name}» перестанет синхронизироваться с этим устройством. Чтобы связать их снова, потребуется новое подтверждение с обеих сторон.'**
  String deviceUnpairBody(String name);

  /// No description provided for @deviceUnpairConfirm.
  ///
  /// In ru, this message translates to:
  /// **'Отвязать'**
  String get deviceUnpairConfirm;

  /// No description provided for @aboutTitle.
  ///
  /// In ru, this message translates to:
  /// **'О приложении'**
  String get aboutTitle;

  /// No description provided for @aboutAuthor.
  ///
  /// In ru, this message translates to:
  /// **'Автор: zaigard'**
  String get aboutAuthor;

  /// No description provided for @aboutLicense.
  ///
  /// In ru, this message translates to:
  /// **'Лицензия: PolyForm Noncommercial 1.0.0 — свободно для любых некоммерческих целей; коммерческое использование — по отдельному разрешению автора.'**
  String get aboutLicense;

  /// No description provided for @aboutHowToUse.
  ///
  /// In ru, this message translates to:
  /// **'Как пользоваться'**
  String get aboutHowToUse;

  /// No description provided for @aboutGuideLibraryTitle.
  ///
  /// In ru, this message translates to:
  /// **'Библиотека'**
  String get aboutGuideLibraryTitle;

  /// No description provided for @aboutGuideLibraryBody.
  ///
  /// In ru, this message translates to:
  /// **'Импортируйте папку или отдельные файлы — теги и обложки подтянутся автоматически, повторный импорт того же файла не создаёт дубль. Долгий тап по треку (на десктопе — правый клик) открывает меню: редактировать (название/исполнитель/альбом/жанр/обложку), добавить в плейлист, поделиться, удалить. Удаление — не безвозвратное: трек попадает в «Удалённые» (вкладка «Плейлисты»), откуда его можно вернуть или стереть по-настоящему.'**
  String get aboutGuideLibraryBody;

  /// No description provided for @aboutGuidePlaylistsTitle.
  ///
  /// In ru, this message translates to:
  /// **'Плейлисты'**
  String get aboutGuidePlaylistsTitle;

  /// No description provided for @aboutGuidePlaylistsBody.
  ///
  /// In ru, this message translates to:
  /// **'Кнопка «+» создаёт новый плейлист. Внутри плейлиста кнопка добавления треков открывает поиск с множественным выбором — можно отметить сразу несколько и добавить их одной кнопкой. Долгий тап (правый клик) по плейлисту в сетке — переименовать, удалить или выбрать обложку (одну из обложек его же треков или картинку из файла). «Избранное» и «Удалённые» — отдельные встроенные карточки в той же сетке.'**
  String get aboutGuidePlaylistsBody;

  /// No description provided for @aboutGuideDevicesTitle.
  ///
  /// In ru, this message translates to:
  /// **'Устройства и сопряжение'**
  String get aboutGuideDevicesTitle;

  /// No description provided for @aboutGuideDevicesBody.
  ///
  /// In ru, this message translates to:
  /// **'Устройства поблизости в локальной сети видны сами, без настройки — на вкладке «Устройства» под заголовком «Найдено рядом». «Добавить» отправляет запрос на сопряжение; на другом устройстве нужно подтвердить его («Разрешить»). Сопряжение работает только внутри одного и того же профиля — если нужно передать что-то в другой профиль (в том числе чужой), используйте «Поделиться» вместо сопряжения.'**
  String get aboutGuideDevicesBody;

  /// No description provided for @aboutGuideShareTitle.
  ///
  /// In ru, this message translates to:
  /// **'«Поделиться»'**
  String get aboutGuideShareTitle;

  /// No description provided for @aboutGuideShareBody.
  ///
  /// In ru, this message translates to:
  /// **'В меню трека пункт «Поделиться» отправляет этот трек (или, по желанию, весь его альбом) любому видимому поблизости устройству — даже не сопряжённому и с другим профилем. Принимающая сторона видит название и обложку и сама решает, принять ли — просто скачивается и добавляется в библиотеку, без слияния профилей.'**
  String get aboutGuideShareBody;

  /// No description provided for @aboutGuideProfilesTitle.
  ///
  /// In ru, this message translates to:
  /// **'Профили'**
  String get aboutGuideProfilesTitle;

  /// No description provided for @aboutGuideProfilesBody.
  ///
  /// In ru, this message translates to:
  /// **'Несколько человек могут делить одно устройство — у каждого своя библиотека и свой список сопряжённых устройств; переключение — карточка профиля на вкладке «Устройства» → «Сменить». Если это, наоборот, второе устройство одного и того же человека — кнопка «Ждать сопряжения» (при создании профиля или из переключателя) делает его копией уже существующего. Удаление профиля необратимо и требует ввода его имени для подтверждения; удалить можно только неактивный профиль.'**
  String get aboutGuideProfilesBody;

  /// No description provided for @aboutVersion.
  ///
  /// In ru, this message translates to:
  /// **'Версия {version}'**
  String aboutVersion(String version);

  /// No description provided for @aboutDescription.
  ///
  /// In ru, this message translates to:
  /// **'AudiLoc — P2P музыкальный плеер с автосинхронизацией библиотеки в локальной сети, без облака и без центрального сервера.'**
  String get aboutDescription;

  /// No description provided for @aboutGithubLink.
  ///
  /// In ru, this message translates to:
  /// **'Исходный код на GitHub'**
  String get aboutGithubLink;

  /// No description provided for @settingsTitle.
  ///
  /// In ru, this message translates to:
  /// **'Настройки'**
  String get settingsTitle;

  /// No description provided for @settingsTheme.
  ///
  /// In ru, this message translates to:
  /// **'Тема'**
  String get settingsTheme;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In ru, this message translates to:
  /// **'Как в системе'**
  String get settingsThemeSystem;

  /// No description provided for @settingsThemeLight.
  ///
  /// In ru, this message translates to:
  /// **'Светлая'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeDark.
  ///
  /// In ru, this message translates to:
  /// **'Тёмная'**
  String get settingsThemeDark;

  /// No description provided for @settingsLanguage.
  ///
  /// In ru, this message translates to:
  /// **'Язык'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageSystem.
  ///
  /// In ru, this message translates to:
  /// **'Как в системе'**
  String get settingsLanguageSystem;

  /// No description provided for @settingsAbout.
  ///
  /// In ru, this message translates to:
  /// **'О приложении'**
  String get settingsAbout;

  /// No description provided for @settingsEraseData.
  ///
  /// In ru, this message translates to:
  /// **'Стереть все данные'**
  String get settingsEraseData;

  /// No description provided for @settingsEraseDataSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Удаляет все профили и настройки — приложение станет как только что установленное'**
  String get settingsEraseDataSubtitle;

  /// No description provided for @settingsEraseDataWarningTitle.
  ///
  /// In ru, this message translates to:
  /// **'Стереть все данные?'**
  String get settingsEraseDataWarningTitle;

  /// No description provided for @settingsEraseDataWarningBody.
  ///
  /// In ru, this message translates to:
  /// **'Будут безвозвратно удалены все профили на этом устройстве — вся библиотека, плейлисты, обложки, список сопряжённых устройств у каждого из них — и настройки языка/темы. Это затрагивает все профили, не только текущий. Отменить это будет нельзя.'**
  String get settingsEraseDataWarningBody;

  /// No description provided for @settingsEraseDataWarningContinue.
  ///
  /// In ru, this message translates to:
  /// **'Продолжить'**
  String get settingsEraseDataWarningContinue;

  /// No description provided for @settingsEraseDataFinalTitle.
  ///
  /// In ru, this message translates to:
  /// **'Последнее подтверждение'**
  String get settingsEraseDataFinalTitle;

  /// No description provided for @settingsEraseDataFinalBody.
  ///
  /// In ru, this message translates to:
  /// **'Чтобы подтвердить, введите «{keyword}»:'**
  String settingsEraseDataFinalBody(String keyword);

  /// No description provided for @settingsEraseDataFinalKeyword.
  ///
  /// In ru, this message translates to:
  /// **'УДАЛИТЬ'**
  String get settingsEraseDataFinalKeyword;

  /// No description provided for @settingsEraseDataFinalButton.
  ///
  /// In ru, this message translates to:
  /// **'Стереть всё безвозвратно'**
  String get settingsEraseDataFinalButton;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
