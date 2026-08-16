import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/l10n.dart';
import '../about/about_screen.dart';
import '../player/models/playback_shortcuts_settings.dart';

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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(l10n.settingsPlayback, style: TextStyle(color: context.colors.onSurfaceMuted)),
          ),
          const _KeyboardShortcutsToggle(),
          const _SeekStepPicker(),
          const _AllowRemoteControlToggle(),
          const _SaveLocalSessionToggle(),
          const _SyncPlaybackStateToggle(),
          const _KeepAliveInBackgroundToggle(),
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

/// See docs/adr/0029-playback-state-sync.md — Space/arrow-key/media-key
/// playback control, on by default. Turning it off doesn't affect
/// anything else on this screen.
class _KeyboardShortcutsToggle extends ConsumerWidget {
  const _KeyboardShortcutsToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(currentPlaybackShortcutsSettingsProvider);
    return SwitchListTile(
      secondary: const Icon(Icons.keyboard_outlined),
      title: Text(l10n.settingsKeyboardShortcuts),
      subtitle: Text(l10n.settingsKeyboardShortcutsSubtitle),
      value: settings.enabled,
      onChanged: (value) =>
          ref.read(changePlaybackShortcutsSettingsProvider)(settings.copyWith(enabled: value)),
    );
  }
}

/// How far Left/Right arrow seeking jumps — only meaningful while
/// [_KeyboardShortcutsToggle] is on, but shown regardless (matching
/// [_ThemePicker]/[_LanguagePicker] always being visible too) rather than
/// disappearing and reappearing as that toggle flips.
class _SeekStepPicker extends ConsumerWidget {
  const _SeekStepPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(currentPlaybackShortcutsSettingsProvider);
    return ListTile(
      leading: const Icon(Icons.fast_forward_outlined),
      title: Text(l10n.settingsSeekStep),
      subtitle: Text(l10n.settingsSeekStepSeconds(settings.seekStepSeconds)),
      onTap: () => _pickSeekStep(context, ref, settings),
    );
  }

  Future<void> _pickSeekStep(BuildContext context, WidgetRef ref, PlaybackShortcutsSettings settings) async {
    final l10n = context.l10n;
    final chosen = await showDialog<int>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l10n.settingsSeekStep),
        children: [
          for (final seconds in PlaybackShortcutsSettings.seekStepChoices)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(seconds),
              child: Row(
                children: [
                  Expanded(child: Text(l10n.settingsSeekStepSeconds(seconds))),
                  if (settings.seekStepSeconds == seconds) const Icon(Icons.check, color: AppTheme.accent),
                ],
              ),
            ),
        ],
      ),
    );
    if (chosen == null) return;
    await ref.read(changePlaybackShortcutsSettingsProvider)(settings.copyWith(seekStepSeconds: chosen));
  }
}

/// See docs/adr/0030-remote-playback-control.md — off by default,
/// device-level (not synced): any already-paired device can control
/// playback here while this is on.
class _AllowRemoteControlToggle extends ConsumerWidget {
  const _AllowRemoteControlToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final allowed = ref.watch(currentAllowRemoteControlProvider);
    return SwitchListTile(
      secondary: const Icon(Icons.settings_remote_outlined),
      title: Text(l10n.settingsAllowRemoteControl),
      subtitle: Text(l10n.settingsAllowRemoteControlSubtitle),
      value: allowed,
      onChanged: (value) => ref.read(changeAllowRemoteControlProvider)(value),
    );
  }
}

/// **On** by default, unlike the two cross-device toggles below — purely
/// local (`LocalPlaybackStateStore`), nothing here is ever sent
/// anywhere, so it doesn't carry the same "still experimental" risk. See
/// docs/adr/0029-playback-state-sync.md.
class _SaveLocalSessionToggle extends ConsumerWidget {
  const _SaveLocalSessionToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final enabled = ref.watch(currentSaveLocalSessionProvider);
    return SwitchListTile(
      secondary: const Icon(Icons.history_outlined),
      title: Text(l10n.settingsSaveLocalSession),
      subtitle: Text(l10n.settingsSaveLocalSessionSubtitle),
      value: enabled,
      onChanged: (value) => ref.read(changeSaveLocalSessionProvider)(value),
    );
  }
}

/// Off by default, marked experimental in its own subtitle — the user
/// asked for this explicitly after the underlying feature needed
/// several follow-up fixes (see docs/adr/0029-playback-state-sync.md's
/// regression log). Independent of [_SaveLocalSessionToggle] — this
/// device's own restore-after-restart no longer depends on this at all.
/// Unlike every other toggle on this screen, this one is profile-wide,
/// not device-level (docs/adr/0032-unified-profile-sync-and-background-mode.md):
/// it's a CRDT row, written directly via [profileSettingsRepositoryProvider]
/// rather than through the `changeXProvider`/`AudilocApp` plumbing the
/// device-level toggles use, so flipping it here propagates to every
/// device sharing this profile.
class _SyncPlaybackStateToggle extends ConsumerWidget {
  const _SyncPlaybackStateToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final enabled = ref.watch(profileSyncEnabledProvider).value ?? false;
    return SwitchListTile(
      secondary: const Icon(Icons.sync_outlined),
      title: Text(l10n.settingsSyncPlaybackState),
      subtitle: Text(l10n.settingsSyncPlaybackStateSubtitle),
      value: enabled,
      onChanged: (value) => ref.read(profileSettingsRepositoryProvider).setSyncPlaybackEnabled(value),
    );
  }
}

/// Only rendered while [_SyncPlaybackStateToggle] is on — background
/// operation only matters if there's something to keep syncing/remote
/// -controlling while the app isn't in the foreground. Device-level (not
/// CRDT), off by default — see
/// docs/adr/0032-unified-profile-sync-and-background-mode.md.
class _KeepAliveInBackgroundToggle extends ConsumerWidget {
  const _KeepAliveInBackgroundToggle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncEnabled = ref.watch(profileSyncEnabledProvider).value ?? false;
    if (!syncEnabled) return const SizedBox.shrink();

    final l10n = context.l10n;
    final enabled = ref.watch(currentKeepAliveInBackgroundProvider);
    return SwitchListTile(
      secondary: const Icon(Icons.all_inclusive_outlined),
      title: Text(l10n.settingsKeepAliveInBackground),
      subtitle: Text(l10n.settingsKeepAliveInBackgroundSubtitle),
      value: enabled,
      onChanged: (value) => ref.read(changeKeepAliveInBackgroundProvider)(value),
    );
  }
}
