import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Shown once, only on a genuinely fresh install (see
/// `ProfilesStore.needsInitialSetup`) — asks for a name for this
/// device's first profile instead of silently calling it "Профиль 1".
/// Anyone else can be added later from the profile switcher on the
/// Устройства screen.
///
/// [onWaitForPairing] covers the other first-run case: this is *not* a
/// new person, it's the same person's second device (ТЗ scenario —
/// phone + laptop, one owner). AudiLoc's identity is always per-device
/// (docs/adr/0013-account-profiles.md) — there's no way to literally
/// share one profile's process/database across two machines — so
/// instead this creates a placeholder profile that adopts the paired
/// device's name the moment pairing is confirmed, which is what "one
/// profile, two devices" looks like from the outside.
class InitialProfileNameScreen extends StatefulWidget {
  const InitialProfileNameScreen({super.key, required this.onSubmit, required this.onWaitForPairing});

  final ValueChanged<String> onSubmit;
  final VoidCallback onWaitForPairing;

  @override
  State<InitialProfileNameScreen> createState() => _InitialProfileNameScreenState();
}

class _InitialProfileNameScreenState extends State<InitialProfileNameScreen> {
  final _controller = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty || _submitting) return;
    setState(() => _submitting = true);
    widget.onSubmit(name);
  }

  void _waitForPairing() {
    if (_submitting) return;
    setState(() => _submitting = true);
    widget.onWaitForPairing();
  }

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
                const Icon(Icons.person_outline, size: 48, color: AppTheme.accent),
                const SizedBox(height: 16),
                const Text(
                  'Как вас зовут?',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Это имя вашего профиля — у него будет своя библиотека и свой '
                  'список сопряжённых устройств. Позже на этом же устройстве можно '
                  'добавить другие профили для других людей.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.onSurfaceMuted, fontSize: 13),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(hintText: 'Имя профиля'),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Начать'),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _submitting ? null : _waitForPairing,
                  child: const Text(
                    'Это моё второе устройство — ждать сопряжения',
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
