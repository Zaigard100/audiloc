import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/profile_session.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/profiles/profile.dart';

/// "Кто использует AudiLoc?" — list known profiles, switch to one, create
/// a new one, or rename an existing one. See
/// docs/adr/0013-account-profiles.md.
Future<void> showProfileSwitcherSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => const _ProfileSwitcherSheet(),
  );
}

class _ProfileSwitcherSheet extends ConsumerStatefulWidget {
  const _ProfileSwitcherSheet();

  @override
  ConsumerState<_ProfileSwitcherSheet> createState() => _ProfileSwitcherSheetState();
}

class _ProfileSwitcherSheetState extends ConsumerState<_ProfileSwitcherSheet> {
  late Future<List<Profile>> _profilesFuture;

  @override
  void initState() {
    super.initState();
    _profilesFuture = ref.read(profilesStoreProvider).list();
  }

  void _refresh() => setState(() => _profilesFuture = ref.read(profilesStoreProvider).list());

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(currentProfileProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Профили', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text(
              'У каждого профиля своя библиотека и свой список сопряжённых устройств. Долгий тап — переименовать.',
              style: TextStyle(color: AppTheme.onSurfaceMuted, fontSize: 12),
            ),
            FutureBuilder<List<Profile>>(
              future: _profilesFuture,
              builder: (context, snapshot) {
                final profiles = snapshot.data;
                if (profiles == null) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final profile in profiles)
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: profile.id == current.id ? AppTheme.accent : AppTheme.surfaceHigh,
                          child: Icon(
                            Icons.person,
                            color: profile.id == current.id ? Colors.white : AppTheme.onSurfaceMuted,
                          ),
                        ),
                        title: Text(profile.name),
                        trailing: profile.id == current.id ? const Icon(Icons.check, color: AppTheme.accent) : null,
                        onTap: profile.id == current.id ? null : () => _switchTo(context, profile.id),
                        onLongPress: () => _renameDialog(context, profile),
                      ),
                  ],
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('Новый профиль'),
              onTap: () => _createDialog(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _switchTo(BuildContext context, String profileId) async {
    Navigator.of(context).pop();
    await ref.read(switchProfileProvider)(profileId);
  }

  Future<void> _createDialog(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Новый профиль'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Имя'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Создать'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    final profile = await ref.read(profilesStoreProvider).create(name);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    await ref.read(switchProfileProvider)(profile.id);
  }

  Future<void> _renameDialog(BuildContext context, Profile profile) async {
    final controller = TextEditingController(text: profile.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Переименовать профиль'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == profile.name) return;

    if (profile.id == ref.read(currentProfileProvider).id) {
      // Renaming the profile actually running right now — also update
      // this device's peer-visible name and the live UI, not just the
      // registry entry. See docs/adr/0013-account-profiles.md.
      await applyActiveProfileRename(
        profilesStore: ref.read(profilesStoreProvider),
        deviceIdentity: ref.read(deviceIdentityServiceProvider),
        current: profile,
        setCurrentProfile: (p) => ref.read(currentProfileProvider.notifier).state = p,
        name: name,
      );
    } else {
      // A different, not-currently-open profile — its device name will
      // resync automatically the next time it's the active session.
      await ref.read(profilesStoreProvider).rename(profile.id, name);
    }
    _refresh();
  }
}
