import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

/// Device-level app settings — currently just the chosen UI language.
/// Deliberately separate from [ProfilesStore]: language is a property of
/// this installation/device, not of any one profile, so it must survive
/// profile switches and stay the same for every profile on this device
/// (see docs/adr/0027-localization.md).
class AppSettingsStore {
  AppSettingsStore(this.appSupportDir);

  final Directory appSupportDir;

  File get _file => File(p.join(appSupportDir.path, 'settings.json'));

  /// `null` means "never explicitly chosen" — the app falls back to
  /// following the system locale (Flutter's default behavior when
  /// `MaterialApp.locale` is left unset) until the user picks one, either
  /// on the language-choice screen on a fresh install or later from the
  /// "О приложении" screen.
  Future<Locale?> languageLocale() async {
    if (!await _file.exists()) return null;
    final json = jsonDecode(await _file.readAsString()) as Map<String, Object?>;
    final code = json['languageCode'] as String?;
    return code == null ? null : Locale(code);
  }

  /// [code] is a bare language code (e.g. `'ru'`, `'en'`) — pass `null` to
  /// clear the explicit choice and go back to following the system locale.
  Future<void> setLanguageCode(String? code) async {
    if (!await appSupportDir.exists()) await appSupportDir.create(recursive: true);
    await _file.writeAsString(jsonEncode({'languageCode': code}));
  }
}
