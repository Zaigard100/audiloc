import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/l10n.dart';
import '../about/about_screen.dart';

/// Settings — reachable from the gear icon on the Устройства tab
/// (replacing what used to be a direct link to "О приложении", now one
/// level deeper). Theme and language here are device-level, not
/// profile-level (docs/adr/0027-localization.md,
/// docs/adr/0028-settings-screen-and-theming.md) — same for everyone
/// sharing this device regardless of whose profile is active.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        children: [
          const _ThemePicker(),
          const _LanguagePicker(),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(l10n.settingsAbout),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutScreen())),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
            title: Text(
              l10n.settingsEraseData,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            subtitle: Text(l10n.settingsEraseDataSubtitle),
            onTap: () => _eraseAllData(context, ref),
          ),
        ],
      ),
    );
  }

  /// Two separate dialogs, not one — a single "are you sure?" is too easy
  /// to reflexively confirm for something this destructive (every profile
  /// on the device, not just the active one). The first is a plain warning
  /// with what's actually about to happen; only past it does the second,
  /// type-to-confirm dialog even appear — same "can't happen by a stray
  /// double-tap" property as the existing per-profile delete flow
  /// (`profile_switcher_sheet.dart._deleteDialog`), just for the
  /// everything-at-once case.
  Future<void> _eraseAllData(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final proceeded = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.settingsEraseDataWarningTitle),
        content: Text(l10n.settingsEraseDataWarningBody),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(l10n.commonCancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(dialogContext).colorScheme.error),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.settingsEraseDataWarningContinue),
          ),
        ],
      ),
    );
    if (proceeded != true || !context.mounted) return;

    final keyword = l10n.settingsEraseDataFinalKeyword;
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) {
          final matches = controller.text.trim() == keyword;
          return AlertDialog(
            title: Text(l10n.settingsEraseDataFinalTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.settingsEraseDataFinalBody(keyword)),
                const SizedBox(height: 4),
                TextField(controller: controller, autofocus: true, onChanged: (_) => setState(() {})),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Theme.of(dialogContext).colorScheme.error),
                onPressed: matches ? () => Navigator.of(dialogContext).pop(true) : null,
                child: Text(l10n.settingsEraseDataFinalButton),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed != true) return;

    // No further UI to update on success — erasing tears down and
    // rebuilds the entire app (see AudilocApp._eraseAllData), including
    // this screen's own route; nothing left here to react to it with.
    await ref.read(eraseAllDataProvider)();
  }
}

/// Same pattern as [_LanguagePicker] below — a `ListTile` showing the
/// current choice, tap opens a picker dialog with a checkmark on the
/// active option.
class _ThemePicker extends ConsumerWidget {
  const _ThemePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final current = ref.watch(currentThemeModeProvider);
    return ListTile(
      leading: const Icon(Icons.palette_outlined),
      title: Text(l10n.settingsTheme),
      subtitle: Text(_label(l10n, current)),
      onTap: () => _pickThemeMode(context, ref, current),
    );
  }

  String _label(AppLocalizations l10n, ThemeMode mode) => switch (mode) {
        ThemeMode.system => l10n.settingsThemeSystem,
        ThemeMode.light => l10n.settingsThemeLight,
        ThemeMode.dark => l10n.settingsThemeDark,
      };

  Future<void> _pickThemeMode(BuildContext context, WidgetRef ref, ThemeMode current) async {
    final l10n = context.l10n;
    final chosen = await showDialog<ThemeMode>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l10n.settingsTheme),
        children: [
          for (final mode in ThemeMode.values)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(mode),
              child: Row(
                children: [
                  Expanded(child: Text(_label(l10n, mode))),
                  if (current == mode) const Icon(Icons.check, color: AppTheme.accent),
                ],
              ),
            ),
        ],
      ),
    );
    if (chosen == null) return;
    await ref.read(changeThemeModeProvider)(chosen);
  }
}

/// Moved here from "О приложении" (docs/adr/0028-settings-screen-and-theming.md)
/// — otherwise identical to the picker that used to live there, same
/// underlying [changeLanguageProvider]/[currentLocaleProvider].
class _LanguagePicker extends ConsumerWidget {
  const _LanguagePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final current = ref.watch(currentLocaleProvider);
    return ListTile(
      leading: const Icon(Icons.language),
      title: Text(l10n.settingsLanguage),
      subtitle: Text(current == null ? l10n.settingsLanguageSystem : _nativeName(current)),
      onTap: () => _pickLanguage(context, ref, current),
    );
  }

  String _nativeName(Locale locale) => switch (locale.languageCode) {
        'ru' => 'Русский',
        'en' => 'English',
        _ => locale.languageCode,
      };

  Future<void> _pickLanguage(BuildContext context, WidgetRef ref, Locale? current) async {
    final l10n = context.l10n;
    // Plain SimpleDialogOption rows with a checkmark rather than
    // RadioListTile: Radio's groupValue/onChanged API is deprecated as of
    // this Flutter version in favor of an ancestor RadioGroup, which would
    // be more machinery than this one-off, two-or-three-option picker
    // needs.
    final chosen = await showDialog<Object>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l10n.settingsLanguage),
        children: [
          for (final option in AppLocalizations.supportedLocales)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(option),
              child: Row(
                children: [
                  Expanded(child: Text(_nativeName(option))),
                  if (current == option) const Icon(Icons.check, color: AppTheme.accent),
                ],
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop('system'),
            child: Row(
              children: [
                Expanded(child: Text(l10n.settingsLanguageSystem)),
                if (current == null) const Icon(Icons.check, color: AppTheme.accent),
              ],
            ),
          ),
        ],
      ),
    );
    if (chosen == null) return;
    await ref.read(changeLanguageProvider)(chosen is Locale ? chosen : null);
  }
}
