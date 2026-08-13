import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../providers/devices_providers.dart';

/// "Синхронизировано N изменений" (ТЗ п.6.6): a quiet, self-clearing hint
/// that a merge just happened — without this, a user whose device was
/// offline for a while has no way to notice anything changed underneath
/// them.
class SyncBadge extends ConsumerWidget {
  const SyncBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(syncBadgeProvider);
    final count = state.recentCount;
    if (count == null || count == 0) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.sync, size: 16, color: AppTheme.accent),
          const SizedBox(width: 8),
          Text('Синхронизировано $count изменени${_plural(count)}',
              style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  String _plural(int count) {
    final mod10 = count % 10;
    final mod100 = count % 100;
    if (mod10 == 1 && mod100 != 11) return 'е';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) return 'я';
    return 'й';
  }
}
