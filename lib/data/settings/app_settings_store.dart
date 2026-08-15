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

  /// Whether this device writes/syncs its own playback position at all
  /// (docs/adr/0029-playback-state-sync.md) — **off** by default: the
  /// user explicitly asked for this once the feature had already needed
  /// several follow-up fixes (see the ADR's regression log), and wants
  /// it opt-in and labeled experimental rather than on by default until
  /// it's proven out more. Off also means this device's own
  /// restore-after-restart stops working, not just the cross-device
  /// sync: both go through the same CRDT row, there's no separate
  /// "local only" write path to keep one alive without the other. See
  /// [SettingsScreen]'s subtitle for this toggle, which spells that
  /// trade-off out for the user.
  Future<bool> sendPlaybackStateSync() async => (await _read())['sendPlaybackStateSync'] as bool? ?? false;

  Future<void> setSendPlaybackStateSync(bool value) => _write('sendPlaybackStateSync', value);

  /// Whether this device acts on an incoming playback-state row written
  /// by a *different* device — **off** by default, same reasoning as
  /// [sendPlaybackStateSync]. Off doesn't affect this device restoring
  /// its own last state after its own restart (that's not "receiving a
  /// sync from elsewhere"), only whether another device's synced pause
  /// silently applies or prompts here at all — see
  /// `handleIncomingPlaybackState`'s `isOwnState` check.
  Future<bool> receivePlaybackStateSync() async =>
      (await _read())['receivePlaybackStateSync'] as bool? ?? false;

  Future<void> setReceivePlaybackStateSync(bool value) => _write('receivePlaybackStateSync', value);

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
