import 'package:audiloc/core/theme/app_theme.dart';
import 'package:audiloc/features/profiles/initial_profile_name_screen.dart';
import 'package:audiloc/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// See docs/adr/0025-sync-and-discovery-reliability.md — several first
/// testers missed the "second device" option entirely when it was a small
/// text link under the prominent "Начать" button, and ended up creating a
/// brand new, unpaired profile instead. The screen is now a choice step
/// first, with both outcomes as equally-weighted buttons.
void main() {
  testWidgets('the choice step shows both options with no name field yet', (tester) async {
    var submitted = '';
    var waitedForPairing = false;

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: InitialProfileNameScreen(
        onSubmit: (name) => submitted = name,
        onWaitForPairing: () => waitedForPairing = true,
      ),
    ));

    expect(find.textContaining('новый профиль'), findsOneWidget);
    expect(find.textContaining('моё второе устройство'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.textContaining('моё второе устройство'));
    await tester.pump();

    expect(waitedForPairing, isTrue);
    expect(submitted, isEmpty);
  });

  testWidgets('choosing "new profile" reveals the name field, and submitting it calls onSubmit',
      (tester) async {
    var submitted = '';

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: InitialProfileNameScreen(
        onSubmit: (name) => submitted = name,
        onWaitForPairing: () {},
      ),
    ));

    await tester.tap(find.textContaining('новый профиль'));
    await tester.pump();

    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Alex');
    await tester.tap(find.text('Начать'));
    await tester.pump();

    expect(submitted, 'Alex');
  });
}
