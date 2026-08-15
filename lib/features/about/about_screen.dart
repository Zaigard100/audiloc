import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/l10n.dart';

/// "О приложении" — author credit, license, language picker, and a short
/// in-app usage guide, reachable from the Устройства tab.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.aboutTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
        children: [
          Center(
            child: Column(
              children: [
                const Icon(Icons.graphic_eq, size: 56, color: AppTheme.accent),
                const SizedBox(height: 8),
                const Text('audiloc', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                const _VersionLabel(),
                const SizedBox(height: 8),
                Text(l10n.aboutAuthor, style: const TextStyle(color: AppTheme.onSurfaceMuted)),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    l10n.aboutLicense,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppTheme.onSurfaceMuted, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const _LanguagePicker(),
          const Divider(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(l10n.aboutHowToUse, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),
          _GuideSection(title: l10n.aboutGuideLibraryTitle, body: l10n.aboutGuideLibraryBody),
          _GuideSection(title: l10n.aboutGuidePlaylistsTitle, body: l10n.aboutGuidePlaylistsBody),
          _GuideSection(title: l10n.aboutGuideDevicesTitle, body: l10n.aboutGuideDevicesBody),
          _GuideSection(title: l10n.aboutGuideShareTitle, body: l10n.aboutGuideShareBody),
          _GuideSection(title: l10n.aboutGuideProfilesTitle, body: l10n.aboutGuideProfilesBody),
        ],
      ),
    );
  }
}

/// Shows the currently-selected language and opens a picker — the only
/// way to change it after the first-run [LanguageChoiceScreen]. See
/// docs/adr/0027-localization.md.
class _LanguagePicker extends ConsumerWidget {
  const _LanguagePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final current = ref.watch(currentLocaleProvider);
    return ListTile(
      leading: const Icon(Icons.language),
      title: Text(l10n.aboutLanguage),
      subtitle: Text(current == null ? l10n.aboutLanguageSystem : _nativeName(current)),
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
        title: Text(l10n.aboutLanguage),
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
                Expanded(child: Text(l10n.aboutLanguageSystem)),
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

class _VersionLabel extends StatelessWidget {
  const _VersionLabel();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        return Text(
          info == null ? ' ' : context.l10n.aboutVersion(info.version),
          style: const TextStyle(color: AppTheme.onSurfaceMuted),
        );
      },
    );
  }
}

class _GuideSection extends StatelessWidget {
  const _GuideSection({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(body, style: const TextStyle(color: AppTheme.onSurfaceMuted)),
      ],
    );
  }
}
