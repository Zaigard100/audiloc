import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/l10n.dart';

const _githubUrl = 'https://github.com/Zaigard100/audiloc';

/// "О приложении" — author credit, a one-line description, license,
/// GitHub link, and a short in-app usage guide. Reachable from Settings
/// (docs/adr/0028-settings-screen-and-theming.md — the language picker
/// that used to live directly on this screen moved there too, alongside
/// theme and "Стереть все данные").
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    l10n.aboutDescription,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.colors.onSurfaceMuted, fontSize: 13),
                  ),
                ),
                const SizedBox(height: 8),
                Text(l10n.aboutAuthor, style: TextStyle(color: context.colors.onSurfaceMuted)),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    l10n.aboutLicense,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.colors.onSurfaceMuted, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => launchUrl(Uri.parse(_githubUrl), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.code, size: 18),
                  label: Text(l10n.aboutGithubLink),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
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
          style: TextStyle(color: context.colors.onSurfaceMuted),
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
        Text(body, style: TextStyle(color: context.colors.onSurfaceMuted)),
      ],
    );
  }
}
