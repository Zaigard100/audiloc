import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../features/player/models/playback_shortcuts_settings.dart';

/// Device-level app settings — UI language, theme mode, playback
/// keyboard shortcuts. Deliberately separate from [ProfilesStore]: these
/// are all properties of this installation/device, not of any one
/// profile, so they must survive profile switches and stay the same for
/// every profile sharing this device (see docs/adr/0027-localization.md,
/// docs/adr/0028-settings-screen-and-theming.md,
/// docs/adr/0029-playback-state-sync.md).
class AppSettingsStore {
  AppSettingsStore(this.appSupportDir);

  final Directory appSupportDir;

  File get _file => File(p.join(appSupportDir.path, 'settings.json'));

  /// `null` means "never explicitly chosen" — the app falls back to
  /// following the system locale (Flutter's default behavior when
  /// `MaterialApp.locale` is left unset) until the user picks one, either
  /// on the language-choice screen on a fresh install or later from
  /// Settings.
  Future<Locale?> languageLocale() async {
    final code = (await _read())['languageCode'] as String?;
    return code == null ? null : Locale(code);
  }

  /// [code] is a bare language code (e.g. `'ru'`, `'en'`) — pass `null` to
  /// clear the explicit choice and go back to following the system locale.
  Future<void> setLanguageCode(String? code) => _write('languageCode', code);

  /// Defaults to [ThemeMode.system] — same "don't force a choice nobody
  /// made yet" reasoning as [languageLocale], except there's no dedicated
  /// first-run screen for it: system-follow is already a fine default for
  /// a fresh install, not just a placeholder waiting to be replaced.
  Future<ThemeMode> themeMode() async {
    final name = (await _read())['themeMode'] as String?;
    return ThemeMode.values.firstWhere((m) => m.name == name, orElse: () => ThemeMode.system);
  }

  Future<void> setThemeMode(ThemeMode mode) => _write('themeMode', mode.name);

  Future<PlaybackShortcutsSettings> playbackShortcutsSettings() async {
    final json = await _read();
    const fallback = PlaybackShortcutsSettings();
    return PlaybackShortcutsSettings(
      enabled: json['keyboardShortcutsEnabled'] as bool? ?? fallback.enabled,
      seekStepSeconds: json['seekStepSeconds'] as int? ?? fallback.seekStepSeconds,
    );
  }

  Future<void> setPlaybackShortcutsSettings(PlaybackShortcutsSettings settings) async {
    if (!await appSupportDir.exists()) await appSupportDir.create(recursive: true);
    final current = await _read();
    await _file.writeAsString(jsonEncode({
      ...current,
      'keyboardShortcutsEnabled': settings.enabled,
      'seekStepSeconds': settings.seekStepSeconds,
    }));
  }

  /// Off by default — remote control is sensitive (any already-paired
  /// device could otherwise change what's playing here), so each device
  /// opts in individually, not the profile as a whole. See
  /// docs/adr/0030-remote-playback-control.md.
  Future<bool> allowRemoteControl() async => (await _read())['allowRemoteControl'] as bool? ?? false;

  Future<void> setAllowRemoteControl(bool value) => _write('allowRemoteControl', value);

  /// Whether this device should try to keep running in the background —
  /// only ever shown in Settings while the profile-wide sync toggle
  /// (`ProfileSettingsRepository`) is on, so sync/remote control keep
  /// working while the app isn't in the foreground. Off by default,
  /// device-level: this device's own OS-level capability, not a choice
  /// any other device in the profile can make for it. See
  /// docs/adr/0032-unified-profile-sync-and-background-mode.md.
  Future<bool> keepAliveInBackground() async => (await _read())['keepAliveInBackground'] as bool? ?? false;

  Future<void> setKeepAliveInBackground(bool value) => _write('keepAliveInBackground', value);

  /// Whether this device remembers its own last-paused track/position
  /// and restores it after its own restart — purely local
  /// (`LocalPlaybackStateStore`), never synced anywhere, independent of
  /// the profile-wide sync toggle (`ProfileSettingsRepository`,
  /// docs/adr/0032-unified-profile-sync-and-background-mode.md). **On**
  /// by default, unlike that one: nothing here ever leaves the device,
  /// so it doesn't carry the same "still experimental" risk.
  Future<bool> saveLocalSession() async => (await _read())['saveLocalSession'] as bool? ?? true;

  Future<void> setSaveLocalSession(bool value) => _write('saveLocalSession', value);

  Future<Map<String, Object?>> _read() async {
    if (!await _file.exists()) return const {};
    return jsonDecode(await _file.readAsString()) as Map<String, Object?>;
  }

  Future<void> _write(String key, Object? value) async {
    if (!await appSupportDir.exists()) await appSupportDir.create(recursive: true);
    final current = await _read();
    await _file.writeAsString(jsonEncode({...current, key: value}));
  }
}
