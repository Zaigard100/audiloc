import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';

/// Startup is otherwise just `runApp` — opening the right profile's
/// database, building its `ProviderContainer` and starting its
/// background services all happens inside `AudilocApp` now, since which
/// profile to use isn't known statically and can change at runtime when
/// the user switches profiles. See docs/adr/0013-account-profiles.md.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  runApp(const AudilocApp());
}
