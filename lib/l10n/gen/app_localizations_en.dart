// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonSave => 'Save';

  @override
  String get commonCreate => 'Create';

  @override
  String get commonBack => 'Back';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonDelete => 'Delete';

  @override
  String commonErrorPrefix(Object error) {
    return 'Error: $error';
  }

  @override
  String get fieldName => 'Name';

  @override
  String get commonDecline => 'Decline';

  @override
  String get commonAllow => 'Allow';

  @override
  String resumePlaybackBody(String trackTitle, String time, String device) {
    return 'Continue with “$trackTitle”, $time, $device?';
  }

  @override
  String get resumePlaybackContinue => 'Continue';

  @override
  String get settingsPlayback => 'Playback';

  @override
  String get settingsKeyboardShortcuts => 'Keyboard control';

  @override
  String get settingsKeyboardShortcutsSubtitle =>
      'Space — pause, arrows — seek, media keys';

  @override
  String get settingsSeekStep => 'Seek step';

  @override
  String settingsSeekStepSeconds(int seconds) {
    return '${seconds}s';
  }

  @override
  String get settingsAllowRemoteControl => 'Allow remote control';

  @override
  String get settingsAllowRemoteControlSubtitle =>
      'Any already-paired device will be able to control playback on this device while this is on';

  @override
  String get settingsSaveLocalSession => 'Save previous session state';

  @override
  String get settingsSaveLocalSessionSubtitle =>
      'This device only, never sent anywhere. Remembers the last track and position and continues from them next launch';

  @override
  String get settingsSendPlaybackStateSync => 'Send playback state';

  @override
  String get settingsSendPlaybackStateSyncSubtitle =>
      'Experimental, may be unstable. Syncs this device\'s last track position to other devices';

  @override
  String get settingsReceivePlaybackStateSync => 'Receive playback state';

  @override
  String get settingsReceivePlaybackStateSyncSubtitle =>
      'Experimental, may be unstable. Lets a position sent by another device apply here, or prompt to continue from it';

  @override
  String get deviceActionResumeHere => 'Play what\'s paused here';

  @override
  String get deviceActionNothingLoaded => 'Nothing loaded';

  @override
  String get deviceActionPickTrack => 'Pick a track and play';

  @override
  String get deviceActionNoTracksAvailable =>
      'No tracks available on this device';

  @override
  String get searchHint => 'Title, artist, album…';

  @override
  String get searchStartTyping => 'Start typing to search';

  @override
  String get searchNothingFound => 'Nothing found';

  @override
  String get pairingRequestTitle => 'Pairing request';

  @override
  String pairingRequestSameProfile(String name) {
    return '“$name” wants to sync with this device.';
  }

  @override
  String pairingRequestDifferentProfile(String name) {
    return '“$name” wants to add this device to their profile. If you agree, this device will switch to the “$name” profile and download its library — your current profile won\'t go anywhere, you can switch back to it via the profile switcher.';
  }

  @override
  String get shareOfferTitle => 'Track shared with you';

  @override
  String shareOfferSingleTrack(String name) {
    return '“$name” wants to share this track.';
  }

  @override
  String shareOfferAlbum(String name, String album, int count) {
    return '“$name” wants to share the album “$album” ($count tracks).';
  }

  @override
  String shareOfferTracks(String name, int count) {
    return '“$name” wants to share $count tracks.';
  }

  @override
  String get shareOfferAccept => 'Accept';

  @override
  String get favoritesTitle => 'Favorites';

  @override
  String get favoritesEmptyTitle => 'No favorite tracks yet';

  @override
  String get favoritesEmptyBody =>
      'Tap the heart on a track — it\'ll show up here';

  @override
  String get trashTitle => 'Trash';

  @override
  String get trashEmpty => 'No deleted tracks';

  @override
  String get trashRestoreTooltip => 'Restore to library';

  @override
  String get trashEraseForeverTooltip => 'Erase forever';

  @override
  String get trashEraseConfirmTitle => 'Erase forever?';

  @override
  String trashEraseConfirmBody(String title) {
    return '“$title” will be erased from disk on this device and disappear from Trash. It can only be brought back by importing it again manually.';
  }

  @override
  String get trashEraseConfirmButton => 'Erase';

  @override
  String trashErasedSnackbar(String title) {
    return '“$title” erased from this device';
  }

  @override
  String get playlistCreateTitle => 'New playlist';

  @override
  String get playlistFallbackName => 'Playlist';

  @override
  String get playlistEmptyTracks => 'No tracks in this playlist yet';

  @override
  String get playlistSearchHint => 'Search tracks';

  @override
  String get playlistAllTracksAdded =>
      'All tracks are already in this playlist';

  @override
  String get playlistNothingFound => 'Nothing found';

  @override
  String get playlistAddButton => 'Add';

  @override
  String playlistAddButtonWithCount(int count) {
    return 'Add ($count)';
  }

  @override
  String get playlistActionRename => 'Rename';

  @override
  String get playlistActionPickCover => 'Choose cover';

  @override
  String get playlistRenameTitle => 'Rename playlist';

  @override
  String get playlistDeleteConfirmTitle => 'Delete playlist?';

  @override
  String playlistDeleteConfirmBody(String name) {
    return '“$name” will be deleted. The tracks themselves stay untouched in your library.';
  }

  @override
  String get playlistCoverFromFile => 'Image from file';

  @override
  String get playlistCoverPickDialogTitle => 'Choose a playlist cover';

  @override
  String get playerNowPlayingTitle => 'Now playing';

  @override
  String get playerNothingPlaying => 'Nothing is playing';

  @override
  String get playerSourceLibrary => 'Playing: Library';

  @override
  String get playerSourceFavorites => 'Playing: Favorites';

  @override
  String playerSourcePlaylist(String name) {
    return 'Playing: Playlist “$name”';
  }

  @override
  String get trackActionEdit => 'Edit';

  @override
  String get trackActionAddToPlaylist => 'Add to playlist';

  @override
  String get trackActionShare => 'Share';

  @override
  String get trackFileNotDownloadedYet =>
      'File hasn\'t been downloaded to this device yet';

  @override
  String get trackDeleteConfirmTitle => 'Delete track from library?';

  @override
  String trackDeleteConfirmBody(String title) {
    return '“$title” will disappear from the library on this device. The file itself isn\'t deleted — you can restore the track from the Trash tab.';
  }

  @override
  String trackDeletedSnackbar(String title) {
    return '“$title” removed from library';
  }

  @override
  String get trackEditTitle => 'Edit track';

  @override
  String get trackEditPickCoverDialogTitle => 'Choose a cover';

  @override
  String get fieldTitle => 'Title';

  @override
  String get fieldArtist => 'Artist';

  @override
  String get fieldAlbum => 'Album';

  @override
  String get fieldGenre => 'Genre';

  @override
  String get shareWholeAlbum => 'Share the whole album';

  @override
  String get nearbyDevicesLabel => 'Nearby devices';

  @override
  String get noNearbyDevices => 'No devices found nearby';

  @override
  String shareSentSnackbar(String name) {
    return 'Sent to “$name”';
  }

  @override
  String get noPlaylistsYet =>
      'No playlists yet — create one on the Playlists tab';

  @override
  String addedToPlaylistSnackbar(String name) {
    return 'Added to “$name”';
  }

  @override
  String get navLibrary => 'Library';

  @override
  String get navPlaylists => 'Playlists';

  @override
  String get navSearch => 'Search';

  @override
  String get navDevices => 'Devices';

  @override
  String get libraryAddTrackTooltip => 'Add track';

  @override
  String get libraryAddFolderTooltip => 'Add folder';

  @override
  String libraryLoadError(Object error) {
    return 'Failed to load library: $error';
  }

  @override
  String get libraryPickFolderDialogTitle => 'Choose a music folder';

  @override
  String get libraryImportStarted => 'Import started…';

  @override
  String libraryImportResult(int imported, int duplicates, int failed) {
    return 'Added: $imported, duplicates skipped: $duplicates, failed: $failed';
  }

  @override
  String get libraryPickFilesDialogTitle => 'Choose tracks';

  @override
  String get librarySortTitle => 'Title';

  @override
  String get librarySortArtist => 'Artist';

  @override
  String get librarySortAddedAt => 'Date added';

  @override
  String get librarySortTooltip => 'Sort';

  @override
  String get libraryEmptyTitle => 'Your library is empty';

  @override
  String get libraryEmptyBody =>
      'Import a music folder — tags and covers are picked up automatically';

  @override
  String get libraryPickFolderButton => 'Choose a folder';

  @override
  String get trackDownloadingIndeterminate => 'downloading…';

  @override
  String trackDownloadingPercent(int percent) {
    return 'downloading $percent%';
  }

  @override
  String get trackWaitingForTransfer =>
      'waiting to transfer from another device';

  @override
  String get startupErrorTitle => 'Couldn\'t start AudiLoc';

  @override
  String get pairingBannerText =>
      'Waiting to pair with a second device — confirm it on the Devices tab';

  @override
  String get onboardingWelcomeTitle => 'Welcome to AudiLoc';

  @override
  String get onboardingWelcomeSubtitle =>
      'Do you already use this on another device of yours, or is this the first time you\'re opening AudiLoc?';

  @override
  String get onboardingNewProfileButton => 'First time here — new profile';

  @override
  String get onboardingSecondDeviceButton =>
      'This is my second device — pair with the first';

  @override
  String get onboardingNameTitle => 'What\'s your name?';

  @override
  String get onboardingNameSubtitle =>
      'This is your profile\'s name — it\'ll have its own library and its own list of paired devices. You can add other profiles for other people on this same device later.';

  @override
  String get onboardingNameHint => 'Profile name';

  @override
  String get onboardingStartButton => 'Get started';

  @override
  String get profilesTitle => 'Profiles';

  @override
  String get profilesSubtitle =>
      'Each profile has its own library and its own list of paired devices. Long-press to rename, the trash icon to delete permanently.';

  @override
  String get profileDeleteTooltip => 'Delete profile';

  @override
  String get profilesNewProfile => 'New profile';

  @override
  String get profilesWaitForPairingTitle =>
      'This is my second device — wait for pairing';

  @override
  String get profilesWaitForPairingSubtitle =>
      'Instead of an empty profile — wait to pair with another device of yours and become a copy of it';

  @override
  String get profileCreateNameHint => 'Name';

  @override
  String get profileRenameTitle => 'Rename profile';

  @override
  String get profileDeleteTitle => 'Delete profile?';

  @override
  String profileDeleteBody(String name) {
    return '“$name” and its entire library — tracks, playlists, covers, list of paired devices — will be permanently deleted. This cannot be undone.';
  }

  @override
  String profileDeleteConfirmPrompt(String name) {
    return 'To confirm, type “$name”:';
  }

  @override
  String get profileDeleteConfirmButton => 'Delete permanently';

  @override
  String profileDeletePartialError(Object error) {
    return 'Profile removed from the list, but some files couldn\'t be erased: $error';
  }

  @override
  String devicesProfileLabel(String name) {
    return 'Profile: $name';
  }

  @override
  String get devicesProfileSubtitle =>
      'Each profile has its own library and its own devices';

  @override
  String get devicesChangeProfile => 'Switch';

  @override
  String get devicesKnownDevicesLabel => 'Known devices';

  @override
  String get devicesNoneFound => 'No devices found on the local network yet';

  @override
  String devicesErrorPrefix(Object error) {
    return 'Error: $error';
  }

  @override
  String get devicesRefreshTooltip => 'Refresh device list';

  @override
  String get devicesNearbyLabel => 'Found nearby';

  @override
  String get devicesUnpaired => 'Not paired';

  @override
  String get devicesAddPeer => 'Add';

  @override
  String devicesPairingRequestSent(String name) {
    return 'Pairing request sent to “$name”';
  }

  @override
  String get devicesFileTransferTitle => 'File transfer';

  @override
  String get devicesAllFilesPresent =>
      'Every known track is already on this device';

  @override
  String devicesQueuedCount(int count) {
    return 'Queued: $count — they\'ll appear on their own once a device with these files is on the network';
  }

  @override
  String syncBadgeMessage(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Synced $count changes',
      one: 'Synced $count change',
    );
    return '$_temp0';
  }

  @override
  String get deviceOnline => 'Online';

  @override
  String get deviceOffline => 'Offline';

  @override
  String deviceLastSeen(String relative) {
    return 'Offline · last seen $relative';
  }

  @override
  String get deviceLastSeenJustNow => 'just now';

  @override
  String deviceLastSeenMinutes(int count) {
    return '$count min ago';
  }

  @override
  String deviceLastSeenHours(int count) {
    return '$count h ago';
  }

  @override
  String deviceLastSeenDays(int count) {
    return '$count d ago';
  }

  @override
  String get deviceSyncNowTooltip => 'Sync now';

  @override
  String get deviceUnpairTooltip => 'Unpair device';

  @override
  String get deviceUnpairTitle => 'Unpair device?';

  @override
  String deviceUnpairBody(String name) {
    return '“$name” will stop syncing with this device. Pairing them again will need a fresh confirmation on both sides.';
  }

  @override
  String get deviceUnpairConfirm => 'Unpair';

  @override
  String get aboutTitle => 'About';

  @override
  String get aboutAuthor => 'Author: zaigard';

  @override
  String get aboutLicense =>
      'License: PolyForm Noncommercial 1.0.0 — free for any non-commercial purpose; commercial use requires the author\'s separate permission.';

  @override
  String get aboutHowToUse => 'How to use it';

  @override
  String get aboutGuideLibraryTitle => 'Library';

  @override
  String get aboutGuideLibraryBody =>
      'Import a folder or individual files — tags and covers are picked up automatically, re-importing the same file never creates a duplicate. Long-press a track (right-click on desktop) to open a menu: edit (title/artist/album/genre/cover), add to playlist, share, delete. Deleting isn\'t permanent — the track lands in Trash (Playlists tab), where you can restore it or erase it for good.';

  @override
  String get aboutGuidePlaylistsTitle => 'Playlists';

  @override
  String get aboutGuidePlaylistsBody =>
      'The “+” button creates a new playlist. Inside a playlist, the add-tracks button opens search with multi-select — you can check several at once and add them with a single button. Long-press (right-click) a playlist in the grid to rename it, delete it, or choose a cover (one of its own tracks\' covers, or an image file). Favorites and Trash are separate built-in cards in the same grid.';

  @override
  String get aboutGuideDevicesTitle => 'Devices and pairing';

  @override
  String get aboutGuideDevicesBody =>
      'Devices nearby on the local network show up on their own, no setup needed — on the Devices tab, under “Found nearby”. “Add” sends a pairing request; it needs to be confirmed (“Allow”) on the other device. Pairing only ever works within the same profile — if you need to send something to a different profile (including someone else\'s), use “Share” instead of pairing.';

  @override
  String get aboutGuideShareTitle => '“Share”';

  @override
  String get aboutGuideShareBody =>
      'The “Share” item in a track\'s menu sends that track (or, if you choose, its whole album) to any device visible nearby — even one that isn\'t paired and is on a different profile. The receiving side sees the title and cover and decides whether to accept — it\'s simply downloaded and added to the library, with no profile merging involved.';

  @override
  String get aboutGuideProfilesTitle => 'Profiles';

  @override
  String get aboutGuideProfilesBody =>
      'Several people can share one device — each with their own library and their own list of paired devices; switch via the profile card on the Devices tab → “Switch”. If instead this is a second device belonging to the same person, the “Wait for pairing” button (when creating a profile, or from the switcher) makes it a copy of the existing one. Deleting a profile is irreversible and requires typing its name to confirm; only an inactive profile can be deleted.';

  @override
  String aboutVersion(String version) {
    return 'Version $version';
  }

  @override
  String get aboutDescription =>
      'AudiLoc — a P2P music player with automatic library sync over the local network, no cloud, no central server.';

  @override
  String get aboutGithubLink => 'Source code on GitHub';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsThemeSystem => 'Follow system';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageSystem => 'Follow system';

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsEraseData => 'Erase all data';

  @override
  String get settingsEraseDataSubtitle =>
      'Deletes every profile and setting — the app becomes like a fresh install';

  @override
  String get settingsEraseDataWarningTitle => 'Erase all data?';

  @override
  String get settingsEraseDataWarningBody =>
      'Every profile on this device will be permanently deleted — its whole library, playlists, covers, list of paired devices — along with language/theme settings. This affects every profile, not just the current one. This cannot be undone.';

  @override
  String get settingsEraseDataWarningContinue => 'Continue';

  @override
  String get settingsEraseDataFinalTitle => 'Final confirmation';

  @override
  String settingsEraseDataFinalBody(String keyword) {
    return 'To confirm, type “$keyword”:';
  }

  @override
  String get settingsEraseDataFinalKeyword => 'DELETE';

  @override
  String get settingsEraseDataFinalButton => 'Erase everything permanently';
}
