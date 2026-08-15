import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Shown once, only on a genuinely fresh install (see
/// `ProfilesStore.needsInitialSetup`).
///
/// First asks the one question that actually branches the whole flow —
/// "новый человек" vs "моё второе устройство" — as two equally-weighted
/// buttons, *before* asking for a name. The original version asked for a
/// name first and buried the second-device option as a small text link
/// underneath the prominent "Начать" button; several first testers never
/// noticed it and created a brand new (empty, unpaired) profile on their
/// second device instead of pairing it to their existing library — see
/// docs/adr/0025-sync-and-discovery-reliability.md. Naming the new profile
/// is now step two, reached only after explicitly choosing "новый
/// профиль", so a first-time user can no longer miss the choice by
/// skimming past it.
///
/// [onWaitForPairing] covers the second-device case: this is *not* a new
/// person, it's the same person's second device (ТЗ scenario — phone +
/// laptop, one owner). AudiLoc's identity is always per-device
/// (docs/adr/0013-account-profiles.md) — there's no way to literally
/// share one profile's process/database across two machines — so instead
/// this creates a placeholder profile that adopts the paired device's
/// name the moment pairing is confirmed, which is what "one profile, two
/// devices" looks like from the outside.
class InitialProfileNameScreen extends StatefulWidget {
  const InitialProfileNameScreen({super.key, required this.onSubmit, required this.onWaitForPairing});

  final ValueChanged<String> onSubmit;
  final VoidCallback onWaitForPairing;

  @override
  State<InitialProfileNameScreen> createState() => _InitialProfileNameScreenState();
}

enum _Step { choose, name }

class _InitialProfileNameScreenState extends State<InitialProfileNameScreen> {
  final _controller = TextEditingController();
  var _step = _Step.choose;
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
            child: _step == _Step.choose ? _buildChoice() : _buildNameEntry(),
          ),
        ),
      ),
    );
  }

  Widget _buildChoice() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.devices_outlined, size: 48, color: AppTheme.accent),
        const SizedBox(height: 16),
        const Text(
          'Добро пожаловать в AudiLoc',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text(
          'Это устройство уже используете вы сами где-то ещё, или это '
          'первый раз, когда вы открываете AudiLoc?',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppTheme.onSurfaceMuted, fontSize: 13),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _submitting ? null : () => setState(() => _step = _Step.name),
          icon: const Icon(Icons.person_add_outlined),
          label: const Text('Здесь я впервые — новый профиль'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _submitting ? null : _waitForPairing,
          icon: _submitting
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.sync_outlined),
          label: const Text('Это моё второе устройство — сопрячь с первым'),
        ),
      ],
    );
  }

  Widget _buildNameEntry() {
    return Column(
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
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Начать'),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _submitting ? null : () => setState(() => _step = _Step.choose),
          child: const Text('Назад'),
        ),
      ],
    );
  }
}
