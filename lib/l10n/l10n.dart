import 'package:flutter/widgets.dart';

import 'gen/app_localizations.dart';

export 'gen/app_localizations.dart';

/// `context.l10n.someKey` instead of the more verbose
/// `AppLocalizations.of(context)!`. Never null in practice — every
/// [BuildContext] used with this lives under [AppLocalizations.delegate]
/// in `app.dart`'s `MaterialApp.router`.
extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
