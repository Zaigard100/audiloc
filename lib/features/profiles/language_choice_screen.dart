import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// The very first thing shown on a genuinely fresh install, before even
/// [InitialProfileNameScreen] — see docs/adr/0027-localization.md. Text
/// here is deliberately hardcoded bilingually rather than pulled from
/// `AppLocalizations`: this screen's whole job is choosing *which*
/// language the rest of the app should speak, so it can't assume one
/// itself. Each button shows its language's own native name, so it reads
/// correctly regardless of which one the device is currently defaulting
/// to.
class LanguageChoiceScreen extends StatelessWidget {
  const LanguageChoiceScreen({super.key, required this.onChosen});

  final ValueChanged<Locale> onChosen;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.language, size: 48, color: AppTheme.accent),
                const SizedBox(height: 16),
                const Text(
                  'Выберите язык\nChoose your language',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => onChosen(const Locale('ru')),
                  child: const Text('Русский'),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => onChosen(const Locale('en')),
                  child: const Text('English'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
