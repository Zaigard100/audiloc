import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/profile_session.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/profiles/profile.dart';
import '../../l10n/l10n.dart';

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
    final l10n = context.l10n;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.profilesTitle, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              l10n.profilesSubtitle,
              style: const TextStyle(color: AppTheme.onSurfaceMuted, fontSize: 12),
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
                        // The active profile can't be deleted — its database
                        // is open and in use (docs/adr/0018-delete-profile.md)
                        // — so it gets the check mark instead of a delete
                        // affordance; only inactive profiles show one.
                        trailing: profile.id == current.id
                            ? const Icon(Icons.check, color: AppTheme.accent)
                            : IconButton(
                                icon: const Icon(Icons.delete_outline, color: AppTheme.onSurfaceMuted),
                                tooltip: l10n.profileDeleteTooltip,
                                onPressed: () => _deleteDialog(context, profile),
                              ),
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
              title: Text(l10n.profilesNewProfile),
              onTap: () => _createDialog(context),
            ),
            ListTile(
              leading: const Icon(Icons.wifi_tethering),
              title: Text(l10n.profilesWaitForPairingTitle),
              subtitle: Text(
                l10n.profilesWaitForPairingSubtitle,
                style: const TextStyle(fontSize: 12),
              ),
              onTap: () => _waitForPairing(context),
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

  /// Same "second device, wait for pairing" flow `InitialProfileNameScreen`
  /// offers on a fresh install (docs/adr/0013-account-profiles.md), but
  /// reachable here too — for adding a new device to an *existing*
  /// profile when other profiles are already registered on this device
  /// (scenario B and A aren't mutually exclusive: one person's second
  /// device, on a computer someone else already has a profile on).
  Future<void> _waitForPairing(BuildContext context) async {
    Navigator.of(context).pop();
    await ref.read(waitForPairingProvider)();
  }

  Future<void> _createDialog(BuildContext context) async {
    final l10n = context.l10n;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.profilesNewProfile),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.profileCreateNameHint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(l10n.commonCancel)),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(l10n.commonCreate),
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
    final l10n = context.l10n;
    final controller = TextEditingController(text: profile.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.profileRenameTitle),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: Text(l10n.commonCancel)),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(l10n.commonSave),
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

  /// [profile] is never the active one here — the trailing delete button
  /// only shows for inactive profiles (see [build]). Irreversible:
  /// requires typing the profile's own name back, on top of the two
  /// buttons, before the destructive action becomes available at all —
  /// see docs/adr/0018-delete-profile.md.
  Future<void> _deleteDialog(BuildContext context, Profile profile) async {
    final l10n = context.l10n;
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) {
          final matches = controller.text.trim() == profile.name;
          return AlertDialog(
            title: Text(l10n.profileDeleteTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.profileDeleteBody(profile.name)),
                const SizedBox(height: 16),
                Text(l10n.profileDeleteConfirmPrompt(profile.name)),
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
                child: Text(l10n.profileDeleteConfirmButton),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed != true) return;

    // The registry write (unregistering) and the directory erasure are
    // two separate steps inside ProfilesStore.delete() — if the second
    // one throws (a file still locked by something, a permissions
    // hiccup, whatever), the first already succeeded. Without a
    // try/finally here, that exception would propagate up out of this
    // unawaited-from-IconButton call, get silently dropped by the
    // framework's error zone, and _refresh() would never run — the sheet
    // would keep showing the "deleted" profile until it happened to
    // rebuild for some unrelated reason (e.g. reopened fresh). Always
    // refresh, and always surface a real failure instead of hiding it.
    try {
      await ref.read(profilesStoreProvider).delete(profile.id);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.profileDeletePartialError(error))),
        );
      }
    } finally {
      _refresh();
    }
  }
}
